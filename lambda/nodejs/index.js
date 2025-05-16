const { S3Client, GetObjectCommand, PutObjectCommand } = require("@aws-sdk/client-s3");
const sharp = require("sharp");

// S3 client
const s3Client = new S3Client({});

const processedBucket = "my-bucket-994482384481";

// Helper to convert S3 stream to Buffer
const streamToBuffer = async (stream) => {
  return new Promise((resolve, reject) => {
    const chunks = [];
    stream.on("data", (chunk) => chunks.push(chunk));
    stream.on("end", () => resolve(Buffer.concat(chunks)));
    stream.on("error", reject);
  });
};

exports.handler = async (event) => {
  const sourceBucket = event.Records[0].s3.bucket.name;
  console.log('============== SENT KEY ==================')
  console.log(typeof event.Records[0].s3.object.key)
  console.log(decodeURIComponent(event.Records[0].s3.object.key))
  console.log(event.Records[0].s3.object.key)
  const sourceKey = decodeURIComponent(event.Records[0].s3.object.key)
  console.log('============== SRC KEY ==================')
   console.log(sourceKey)
  try {
    // 1. Get image from source S3 bucket
    const getObjCommand = new GetObjectCommand({
      Bucket: sourceBucket,
      Key: sourceKey
    });
    const { Body } = await s3Client.send(getObjCommand);
    const imageBuffer = await streamToBuffer(Body);

    // 2. Process the image using sharp
    const processedImage = await sharp(imageBuffer)
      .resize(300)
      .grayscale()
      .toFormat('png')
      .toBuffer();

    // 3. Construct destination key
    // const filename = sourceKey.split('/').pop().replace(/\.\w+$/, '.png');
    const destinationKey = `processed/${sourceKey.replace('uploads/', '')}`;

    // 4. Upload to processed bucket
    const putObjCommand = new PutObjectCommand({
      Bucket: processedBucket,
      Key: destinationKey,
      Body: processedImage,
      ContentType: 'image/png'
    });

    await s3Client.send(putObjCommand);

    console.log(`Image processed and stored at s3://${processedBucket}/${destinationKey}`);
    return {
      statusCode: 200,
      body: 'Image processed and uploaded successfully.'
    };

  } catch (err) {
    console.error('Image processing failed:', err);
    throw err;
  }
};

