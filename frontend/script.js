const publicip = '18.228.88.189';
const url= `http://${publicip}`
let token;
let presignedurl;
let objid;

function checkauth(){
  const ltoken = localStorage.getItem('token')
  if (ltoken){
   authenticated.style.display = 'unset'
   token = ltoken
  }
}


const loading = document.getElementById('loading');
const authing = document.getElementById('authing');

const authenticated = document.getElementById('authenticated');

  const fileInput = document.getElementById('fileInput');
  const startbtn = document.getElementById('start-btn');
  const authbtn = document.getElementById('auth-btn');
  const preview = document.getElementById('preview');

        const progressarea = document.getElementById('progress-area')
checkauth()

async function auth(){
  authing.style.display = 'unset'
  authbtn.disabled = true

  try{
    const response = await fetch(`${url}/auth`, {
      method: 'GET',
    });
    data = await response.json();
    authbtn.disabled = false
   authing.style.display = 'none'
   authenticated.style.display = 'unset'
   token = data.token
   localStorage.setItem('token', token)
   console.log(token)
  } catch(err){
    authbtn.disabled = false
   authing.style.display = 'none'
  }
}



  fileInput.addEventListener('change', function () {
      const file = this.files[0];
      if (file && file.type.startsWith('image/')) {
          startbtn.style.display = 'unset'
        const reader = new FileReader();
        reader.onload = function (e) {
          preview.src = e.target.result;
          preview.style.display = 'block';
        };
        reader.readAsDataURL(file);
      } else {
        startbtn.style.display = 'none'
        preview.style.display = 'none';
      }
    });

    const uploadBtn = document.getElementById('uploadBtn');


    uploadBtn.addEventListener('click', function () {
      fileInput.click();
    });

async function uploadImage() {
    const fileInput = document.getElementById('fileInput');
    const file = fileInput.files[0];

    if (!file || file.type !== 'image/jpeg') {
    alert('Please select a .jpg file');
    return;
    }

    startbtn.disabled = true
    try{

      const response = await fetch(`${url}/get-put-pre-signed-url`, {
        method: 'GET',
        headers: {
          'Authorization': token
        }
      });
      data = await response.json();
      presignedurl = data.url
      objid = data.objid
      
      const uploadResponse = await fetch(presignedurl, {
        method: 'PUT',
        body: file
      });

      if (uploadResponse.ok) {
          console.log('Upload successful!');
          await checkState()
      } else {
        alert('Upload failed.');
          startbtn.disabled = false
        }
      } catch(err){
      startbtn.disabled = false
      alert('Upload failed.');
    }
}



let state = null 

async function checkState(){
  progressarea.style.display = 'flex'
  const p = document.createElement('p')
  p.innerText = 'polling server for status...'
  progressarea.append(p)
    await new Promise(async (resolve, reject) => {
        const i = setInterval(async () => {
            if (state == 'ready') {
                clearInterval(i)
                resolve()
            }
            await fetchprocess()
        }, 400);
    })
    await getGetPreSignedUrl()
    console.log('done')
    startbtn.disabled = false
}

async function fetchprocess(){
        const response = await fetch(`${url}/check-process/${objid}`, {
        method: 'GET',
        headers: {
          'Authorization': token
        }
      });
      data = await response.json();
      console.log(data.processdata)
      state = data.processdata.state

      const p = document.createElement('p')
      p.innerText = `${state}...`
      progressarea.append(p)
      progressarea.scrollTop = progressarea.scrollHeight;
}

async function getGetPreSignedUrl(){
        const response = await fetch(`${url}/get-get-pre-signed-url/${objid}`, {
        method: 'GET',
        headers: {
          'Authorization': token
        }
      });
    data = await response.json();
    if (data.ready){
        await requestToS3BucketGetURL(data.url)
    } else {
        alert('not ready yet')
    }
}

async function requestToS3BucketGetURL(geturl){
     const response = await fetch(geturl, {
        method: 'GET',
      })
      if (response.ok){
        console.log('it seems it worked')
        await createImageOnPage(response.url)
    } else {
            console.log('not wkoring')
        }
    console.log(response)
}

async function createImageOnPage(finalobjurl){
  const img = document.createElement('img')
  img.setAttribute('src', finalobjurl)
  document.body.append(img)
}