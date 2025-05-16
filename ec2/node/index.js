const https = require('https');
const express = require('express')
const redis = require('redis')
const cors = require('cors')
const jwt = require('jsonwebtoken')
const app = express()
const bodyParser = require('body-parser')
const { S3Client, PutObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');

// The region your EC2 instance and S3 bucket are in
const REGION = "sa-east-1";
const BUCKET_NAME = "my-bucket-157463745";
const SECOND_BUCKET_NAME = "my-bucket-994482384481"
const s3Client = new S3Client({ region: REGION });


app.use(bodyParser.urlencoded())
app.use(bodyParser.json())
app.use(bodyParser.text({ type: 'text/plain' }))
app.use(cors());

const client = redis.createClient({
	  socket: {
    host: '127.0.0.1',
    port: 6379
  },
  password: 'my_very_secure_password'
})


function tryConnect() {
  client.connect()
    .then(() => {
      console.log('Connected to Redis!');
    })
    .catch((err) => {
      console.error('Failed to connect. Retrying in 5 seconds...');
      setTimeout(tryConnect, 5000);
    });
}

tryConnect();


async function storeUserData(key, data) {
  try {
    await client.setEx(key, 300, JSON.stringify(data))
  } catch (err) {
    console.error('Redis error:', err);
  }
}

async function getUserData(key) {
  const value = await client.get(key);
  return JSON.parse(value);
}

async function generatePutPreSignedUrl(userid, objid){
  const key = `uploads/${userid}/${objid}.jpg`
  const command = new PutObjectCommand({ Bucket: BUCKET_NAME, Key: key })    //content-type
  const signedUrl = await getSignedUrl(s3Client, command, { expiresIn: 2000 })
  return signedUrl
}

async function generateGetPreSignedUrl(userid, objid){
  const key = `processed/${userid}/${objid}.jpg`
  const command = new GetObjectCommand({ Bucket: SECOND_BUCKET_NAME, Key: key })    //content-type
  const signedUrl = await getSignedUrl(s3Client, command, { expiresIn: 2000 })
  return signedUrl;
}

const SECRET_KEY='my-very-secret'
function generateToken(username, userid) {
	const payload = { username, userid }
	const token = jwt.sign(payload, SECRET_KEY, { expiresIn: '24h' })
	return token
}

function verifyToken(token){
	try {
	    	const decoded = jwt.verify(token, SECRET_KEY);
	    	return decoded
	} catch (err) {
		console.error('Invalid or expired token');
		return null
	}
}

app.get('/auth', (req,res) => {
	const token = generateToken('admin', String(Math.random()))
	res.json({token})
	return res.end()
})


//put url
app.get('/get-put-pre-signed-url', async (req,res) => {
    const token = req.headers.authorization
    const data = verifyToken(token)
	if (!data) {
		res.status(403)
		res.send('not allowed');
		return res.end()
	} else {
		const objid = String(Math.random())
		const rediskey = `${data.userid}:${objid}`
		await storeUserData((rediskey), {state: 'uploading'})
		const url = await generatePutPreSignedUrl(data.userid, objid)
		res.status(200)
		res.json({url, objid})
		return res.end()
	}
})

app.get('/check-process/:obj_id', async (req,res) => {
	const token = req.headers.authorization
    	const data = verifyToken(token)
	if (!data) {
		res.status(403)
		res.send('not allowed');
		return res.end()
	} else {
		const objid = req.params.obj_id
		const processdata = await getUserData(`${data.userid}:${objid}`)
		res.status(200)
		return res.json({processdata})
	}
})


app.get('/get-get-pre-signed-url/:obj_id', async (req,res) => {
	const token = req.headers.authorization
    	const data = verifyToken(token)
	if (!data) {
		res.status(403)
		res.send('not allowed');
		return res.end()
	} else {
		const objid = req.params.obj_id
		const processdata = await getUserData(`${data.userid}:${objid}`)
		if (processdata.state == 'ready') {
			const url = await generateGetPreSignedUrl(data.userid, objid)
			res.status(200)
			res.json({url, ready: true})
			return res.end()
		} else {
			res.status(202)
			res.json({ready: false})
			return res.end()
		}
	}
})

app.post('/notify', async (req,res) => {

   	const messageType = req.headers['x-amz-sns-message-type'];

	if(messageType == "SubscriptionConfirmation"){
		const surl = JSON.parse(req.body).SubscribeURL
   		https.get(surl, (cres) => {
			console.log('ok: ' + cres.statusCode)
   		})
		return res.end()
	}

	else if (messageType === 'Notification') {
		console.log('notification')
		//console.log(typeof req.body)
		//console.log(typeof JSON.parse(req.body))
        	//const message = JSON.parse(req.body.Message)
        	//const message = JSON.parse(req.body).Message
		//console.log('message')
		//console.log(message)
		//console.log(typeof message)
		const parsedBody = JSON.parse(req.body);
                const message = JSON.parse(parsedBody.Message) 
		const objectKey = message.Records[0].s3.object.key;
		const userid = objectKey.split('/')[1]
		const objid = objectKey.split('/')[2].replace('.jpg', '')
		console.log('userid and objid')
		console.log(userid)
		console.log(objid)
		await storeUserData(`${userid}:${objid}`, {state: 'ready'})
		return res.status(200).end()
	} else {
		console.log('third option')
		return res.end()
	}
})

app.listen(80, ()=> console.log('listening'))
