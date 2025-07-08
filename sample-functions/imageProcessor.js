const { BlobServiceClient } = require('@azure/storage-blob');
const sharp = require('sharp');

module.exports = async function (context, eventHubMessages) {
    context.log('Image processing function triggered');
    
    const storageConnectionString = process.env.STORAGE_CONNECTION_STRING;
    const originalContainer = process.env.ORIGINAL_IMAGES_CONTAINER;
    const processedContainer = process.env.PROCESSED_IMAGES_CONTAINER;
    
    const blobServiceClient = BlobServiceClient.fromConnectionString(storageConnectionString);
    const originalContainerClient = blobServiceClient.getContainerClient(originalContainer);
    const processedContainerClient = blobServiceClient.getContainerClient(processedContainer);
    
    for (const message of eventHubMessages) {
        try {
            context.log('Processing message:', JSON.stringify(message));
            
            // Extract blob info from Event Grid message
            const blobUrl = message.data.url;
            const blobName = message.data.url.split('/').pop();
            
            context.log(`Processing image: ${blobName}`);
            
            // Download the original image
            const originalBlobClient = originalContainerClient.getBlobClient(blobName);
            const downloadResponse = await originalBlobClient.download();
            
            // Convert stream to buffer
            const chunks = [];
            for await (const chunk of downloadResponse.readableStreamBody) {
                chunks.push(chunk);
            }
            const imageBuffer = Buffer.concat(chunks);
            
            // Convert image to grayscale using Sharp
            const processedImageBuffer = await sharp(imageBuffer)
                .grayscale()
                .jpeg({ quality: 90 })
                .toBuffer();
            
            // Upload processed image
            const processedBlobName = `processed_${blobName}`;
            const processedBlobClient = processedContainerClient.getBlobClient(processedBlobName);
            
            await processedBlobClient.upload(processedImageBuffer, processedImageBuffer.length, {
                blobHTTPHeaders: {
                    blobContentType: 'image/jpeg'
                }
            });
            
            context.log(`Successfully processed and uploaded: ${processedBlobName}`);
            
        } catch (error) {
            context.log.error(`Error processing image: ${error.message}`);
            throw error;
        }
    }
};