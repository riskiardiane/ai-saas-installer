const axios = require('axios');
const cheerio = require('cheerio');

class TikTokDownloader {
  constructor() {
    this.apiUrl = 'https://myapi.app/api';
    this.sitename = 'tikmate.cc';
  }

  async analyzeVideo(tiktokUrl) {
    try {
      const response = await axios.post(`${this.apiUrl}/analyze`, 
        new URLSearchParams({
          url: tiktokUrl,
          sitename: this.sitename
        }), {
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded'
          }
        }
      );

      const data = response.data;

      if (data.error === true) {
        throw new Error('Failed to analyze video');
      }

      let medias = data.medias.filter(media => media.quality !== 'watermark');

      medias = medias.map(media => ({
        ...media,
        extension: media.extension?.toUpperCase() || 'MP4',
        quality: this.formatQuality(media.quality)
      }));

      return {
        id: data.id,
        title: data.title,
        author: data.author,
        thumbnail: data.thumbnail,
        duration: data.duration,
        filename: data.filename,
        medias: medias.reverse()
      };

    } catch (error) {
      console.error('Error analyzing video:', error.message);
      throw error;
    }
  }

  formatQuality(quality) {
    const qualityMap = {
      'hd_no_watermark': '1080p',
      'no_watermark': '720p',
      'audio': '128kbps'
    };
    return qualityMap[quality] || quality;
  }

  async convertToMP3(videoUrl, videoId) {
    try {
      const response = await axios.post(`${this.apiUrl}/converter`, 
        new URLSearchParams({
          url: videoUrl,
          id: videoId
        }), {
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded'
          }
        }
      );

      const data = response.data;

      if (data.error === false) {
        return {
          success: true,
          downloadUrl: `${this.apiUrl}/downloader?id=${data.url}&site=${this.sitename}`
        };
      } else {
        throw new Error('Conversion failed');
      }

    } catch (error) {
      console.error('Error converting to MP3:', error.message);
      throw error;
    }
  }

  getDownloadUrl(mediaUrl) {
    return `${this.apiUrl}/download?url=${encodeURIComponent(mediaUrl)}&sitename=${this.sitename}`;
  }

  async downloadVideo(mediaUrl, outputPath) {
    const fs = require('fs');
    const downloadUrl = this.getDownloadUrl(mediaUrl);

    try {
      const response = await axios({
        method: 'GET',
        url: downloadUrl,
        responseType: 'stream'
      });

      const writer = fs.createWriteStream(outputPath);
      response.data.pipe(writer);

      return new Promise((resolve, reject) => {
        writer.on('finish', resolve);
        writer.on('error', reject);
      });

    } catch (error) {
      console.error('Error downloading video:', error.message);
      throw error;
    }
  }
}

/** jika butuh fungsi main nya ini ya
async function main() {
  const downloader = new TikTokDownloader();
  const url = "https://vt.tiktok.com/ZSPrmoRNv/";

  try {
    const data = await downloader.analyzeVideo(url);

    const result = {
      id: data.id,
      title: data.title,
      author: data.author,
      duration: data.duration,
      thumbnail: data.thumbnail,
      filename: data.filename,
      medias: data.medias || []
    };

    console.log(JSON.stringify(result, null, 2));

  } catch (err) {
    console.log(JSON.stringify({
      error: true,
      message: err.message
    }, null, 2));
  }
}

main();
 */