const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');
const zlib = require('zlib');

class BilibiliDownloader {
  constructor() {
    this.headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:146.0) Gecko/20100101 Firefox/146.0',
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.5',
      'Origin': 'https://www.bilibili.tv',
      'Referer': 'https://www.bilibili.tv/',
      'Connection': 'keep-alive',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'cross-site'
    };
  }

  parseUrl(url) {
    const patterns = [
      /bilibili\.tv\/(?:en|id|[a-z]{2})\/video\/(\d+)/i,
      /bilibili\.tv\/video\/(\d+)/i,
      /^(\d{10,})$/
    ];

    for (const pattern of patterns) {
      const match = url.match(pattern);
      if (match) {
        return match[1];
      }
    }
    return null;
  }

  async getPlayUrl(aid, qn = 64) {
    const apiUrl = `https://api.bilibili.tv/intl/gateway/web/playurl?s_locale=id_ID&platform=web&aid=${aid}&qn=${qn}&type=0&device=wap&tf=0&force_container=2&spm_id=bstar-web.ugc-video-detail.0.0&from_spm_id=bstar-web.homepage.trending.all`;
    
    return new Promise((resolve, reject) => {
      https.get(apiUrl, { headers: this.headers }, (res) => {
        const chunks = [];
        let stream = res;
        
        const encoding = res.headers['content-encoding'];
        if (encoding === 'gzip') {
          stream = res.pipe(zlib.createGunzip());
        } else if (encoding === 'deflate') {
          stream = res.pipe(zlib.createInflate());
        } else if (encoding === 'br') {
          stream = res.pipe(zlib.createBrotliDecompress());
        }
        
        stream.on('data', (chunk) => {
          chunks.push(chunk);
        });
        
        stream.on('end', () => {
          try {
            const data = Buffer.concat(chunks).toString('utf-8');
            if (data.length === 0) {
              return reject(new Error('Empty response from API'));
            }
            const json = JSON.parse(data);
            resolve(json);
          } catch (e) {
            reject(new Error(`Failed to parse API response: ${e.message}`));
          }
        });
        
        stream.on('error', reject);
      }).on('error', reject);
    });
  }

  async downloadFile(url, outputPath, onProgress) {
    return new Promise((resolve, reject) => {
      const parsedUrl = new URL(url);
      const protocol = parsedUrl.protocol === 'https:' ? https : http;
      
      const file = fs.createWriteStream(outputPath);
      
      const request = protocol.get(url, { headers: this.headers }, (response) => {
        if (response.statusCode === 302 || response.statusCode === 301) {
          file.close();
          fs.unlinkSync(outputPath);
          return this.downloadFile(response.headers.location, outputPath, onProgress)
            .then(resolve)
            .catch(reject);
        }
        
        if (response.statusCode !== 200) {
          file.close();
          fs.unlinkSync(outputPath);
          return reject(new Error(`Failed to download: ${response.statusCode}`));
        }
        
        const totalSize = parseInt(response.headers['content-length'], 10);
        let downloadedSize = 0;
        
        response.on('data', (chunk) => {
          downloadedSize += chunk.length;
          if (onProgress && totalSize) {
            const percent = ((downloadedSize / totalSize) * 100).toFixed(2);
            onProgress(downloadedSize, totalSize, percent);
          }
        });
        
        response.pipe(file);
        
        file.on('finish', () => {
          file.close();
          resolve(outputPath);
        });
      });
      
      request.on('error', (err) => {
        fs.unlinkSync(outputPath);
        reject(err);
      });
      
      file.on('error', (err) => {
        fs.unlinkSync(outputPath);
        reject(err);
      });
    });
  }

  async downloadVideo(aid, quality = 16, outputDir = './downloads') {
    try {
      const data = await this.getPlayUrl(aid, quality);
      
      if (data.code !== 0) {
        throw new Error(`API Error: ${data.message}`);
      }
      
      const playurl = data.data.playurl;
      const videos = playurl.video;
      
      if (!videos || videos.length === 0) {
        throw new Error('No video found');
      }
      
      const video = videos.find(v => v.stream_info.quality === quality) || videos[0];
      const videoUrl = video.video_resource.url;
      const backupUrl = video.video_resource.backup_url?.[0];
      
      if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
      }
      
      const filename = `bilibili_${aid}_${quality}.mp4`;
      const outputPath = path.join(outputDir, filename);
      
      try {
        await this.downloadFile(videoUrl, outputPath, (downloaded, total, percent) => {
          process.stdout.write(`\r${percent}% (${(downloaded / 1024 / 1024).toFixed(2)}MB / ${(total / 1024 / 1024).toFixed(2)}MB)`);
        });
        
        console.log(`\n${outputPath}`);
        
      } catch (err) {
        if (backupUrl) {
          await this.downloadFile(backupUrl, outputPath, (downloaded, total, percent) => {
            process.stdout.write(`\r${percent}% (${(downloaded / 1024 / 1024).toFixed(2)}MB / ${(total / 1024 / 1024).toFixed(2)}MB)`);
          });
          
          console.log(`\n${outputPath}`);
        } else {
          throw err;
        }
      }
      
      return outputPath;
      
    } catch (error) {
      console.error(error.message);
      throw error;
    }
  }
}

const downloader = new BilibiliDownloader();
const aid = 'https://bilibili.tv/video/4797959484348416';
const quality = 64;

downloader.downloadVideo(aid, quality)
  .catch((err) => {
    process.exit(1);
  });