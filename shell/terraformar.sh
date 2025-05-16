cd ~/img-upload-project/terraform
rm -f terraform.tfvars
touch terraform.tfvars
echo 'aws_region="sa-east-1"' >> terraform.tfvars
echo 'aws_az="sa-east-1a"' >> terraform.tfvars
echo "my_ip = \"$(curl -s ifconfig.me)/32\"" >> terraform.tfvars

terraform validate
terraform apply -auto-approve -lock=false

web_public_ip=$(terraform output -raw eip)
sns_arn=$(terraform output -raw sns_arn)

cd ~/img-upload-project/ansible
rm -f inventory.ini
rm -f playbook.yml
rm -f ansible2.cfg

touch inventory.ini
cat << EOF > inventory.ini
[webserver]
webserver
EOF

cd ~/.ssh/
rm -f ~/.ssh/config
touch config
cat << EOF > config
Host webserver
    Hostname ${web_public_ip}
    User ubuntu
    IdentityFile ~/.ssh/meu-par-de-chaves.pem
    IdentitiesOnly yes
    StrictHostKeyChecking no
EOF

cd ~/img-upload-project/ansible
touch playbook.yml
cat << EOF > playbook.yml
- name: set up nodejs and docker server
  hosts: webserver
  become: yes
  tasks:
    - name: run apt update
      apt:
        update_cache: yes
        cache_valid_time: 3600

    - name: Install python.
      package:
        name: "{{ item }}"
        state: present
      loop:
        - python3
        - unzip

    - name: Install required packages for AWS CLI
      apt:
        name:
          - curl
          - unzip
        state: present

    - name: Download AWS CLI installer
      get_url:
        url: "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
        dest: "/tmp/awscliv2.zip"

    - name: Unzip AWS CLI installer
      unarchive:
        src: "/tmp/awscliv2.zip"
        dest: "/tmp"
        remote_src: yes

    - name: Run AWS CLI installer
      command: "/tmp/aws/install"

    - name: Verify AWS CLI installation
      command: "aws --version"
      register: aws_cli_version

    - name: Display AWS CLI version
      debug:
        msg: "{{ aws_cli_version.stdout }}"

##start aws config##
    - name: Add Docker GPG key
      apt_key:
        url: https://download.docker.com/linux/ubuntu/gpg
        state: present

    - name: Add Docker APT repository
      apt_repository:
        repo: "deb [arch=amd64] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable"
        state: present

    - name: Install Docker
      apt:
        name:
          - docker-ce
          - docker-ce-cli
          - containerd.io
        state: present

    - name: Pull Redis image
      docker_image:
        name: redis
        source: pull

    - name: Run Redis container
      docker_container:
        name: redis-server
        image: redis
        state: started
        restart_policy: always
        ports:
          - "6379:6379"
        command: redis-server --requirepass "my_very_secure_password" --bind 0.0.0.0

    - name: Add NodeSource APT repo for Node.js 18.x
      shell: curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
      args:
        executable: /bin/bash

    - name: Install Node.js and npm
      apt:
        name: nodejs
        state: present

    - name: Create ~/app directory
      file:
        path: /home/ubuntu/app
        state: directory
        mode: '0755'
        owner: "ubuntu"
        group: "ubuntu"

    - name: Run npm init
      shell: npm init -y
      args:
        chdir: /home/ubuntu/app

    - name: Install required npm packages
      shell: npm install @aws-sdk/client-s3 @aws-sdk/s3-request-presigner express body-parser redis cors jsonwebtoken
      args:
        chdir: /home/ubuntu/app

    - name: Copy file to EC2
      copy:
        src: /home/guilherme/img-upload-project/node/index.js
        dest: /home/ubuntu/app/index.js
        owner: "ubuntu"
        group: "ubuntu"
        mode: '0644'

    - name: Install pm2 globally
      npm:
        name: pm2
        global: yes

    - name: Start Node.js app with pm2
      shell: >
        pm2 start index.js --name my-app
        --output /home/ubuntu/app/logs/out.log
        --error /home/ubuntu/app/logs/error.log
      args:
        chdir: /home/ubuntu/app

    - name: Subscribe EC2 to SNS topic
      shell: |
        aws sns subscribe \
          --topic-arn ${sns_arn} \
          --protocol http \
          --notification-endpoint http://${web_public_ip}:80/notify \
          --region sa-east-1
      environment:
        AWS_ACCESS_KEY_ID: "{{ aws_access_key }}"
        AWS_SECRET_ACCESS_KEY: "{{ aws_secret_key }}"

     ##unset aws ci (to use ec2 role instead)##

    - name: Unset AWS-CLI (to use ec2 role instead)
      file:
        path: /home/ec2-user/.aws/credentials
        state: absent

    - name: Remove AWS config file
      file:
        path: /home/ec2-user/.aws/config
        state: absent

    - name: Unset AWS environment variables in profile (if they were added there)
      lineinfile:
        path: /home/ec2-user/.bash_profile
        regexp: '^export AWS_'
        state: absent

    - name: Ensure AWS environment variables are not set in current session
      shell: |
        unset AWS_ACCESS_KEY_ID
        unset AWS_SECRET_ACCESS_KEY
        unset AWS_SESSION_TOKEN
        unset AWS_PROFILE
      args:
        executable: /bin/bash
    - name: Remove AWS config/credentials from root user
      file:
        path: "/root/.aws"
        state: absent

EOF

ansible-playbook -i inventory.ini playbook.yml -e "aws_access_key=$AWS_ACCESS_KEY_ID aws_secret_key=$AWS_SECRET_ACCESS_KEY"
