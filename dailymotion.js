const https = require('https');
const http = require('http');
const fs = require('fs');
const { URL } = require('url');

function fetchUrl(url) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const protocol = urlObj.protocol === 'https:' ? https : http;
    
    const options = {
      hostname: urlObj.hostname,
      path: urlObj.pathname + urlObj.search,
      method: 'GET',
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Mobile Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': 'https://cse.knospe.co'
      }
    };

    const req = protocol.request(options, (res) => {
      let data = '';

      res.on('data', (chunk) => {
        data += chunk;
      });

      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve({
            ok: true,
            status: res.statusCode,
            data: data
          });
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${data}`));
        }
      });
    });

    req.on('error', (error) => {
      reject(error);
    });

    req.end();
  });
}

function parseSRT(srtContent) {
  const subtitles = [];
  const blocks = srtContent.trim().split(/\n\s*\n/);

  for (const block of blocks) {
    const lines = block.trim().split('\n');
    if (lines.length < 3) continue;

    const timestampLine = lines[1];
    const match = timestampLine.match(/(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})/);
    
    if (match) {
      const startTime = match[1];
      const endTime = match[2];
      const text = lines.slice(2).join('\n').trim();

      subtitles.push({
        timestamp: `${startTime} --> ${endTime}`,
        text: text
      });
    }
  }

  return subtitles;
}

async function fetchSubtitles(subtitleData) {
  if (!subtitleData) return null;

  const allSubtitles = {};

  for (const [lang, info] of Object.entries(subtitleData)) {
    if (info.urls && info.urls.length > 0) {
      try {
        const srtUrl = info.urls[0];
        const response = await fetchUrl(srtUrl);
        
        if (response.ok) {
          const parsed = parseSRT(response.data);
          allSubtitles[lang] = {
            label: info.label,
            subtitles: parsed
          };
        }
      } catch (error) {
        console.error(`Error fetching subtitle for ${lang}:`, error.message);
      }
    }
  }

  return Object.keys(allSubtitles).length > 0 ? allSubtitles : null;
}

function extractVideoId(url) {
  const patterns = [
    /dailymotion\.com\/video\/([a-zA-Z0-9]+)/,
    /dai\.ly\/([a-zA-Z0-9]+)/,
    /video\/([a-zA-Z0-9]+)\.json/
  ];

  for (const pattern of patterns) {
    const match = url.match(pattern);
    if (match) return match[1];
  }

  return null;
}

function generateUUID() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}

function generateViewId() {
  const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
  let id = '';
  for (let i = 0; i < 18; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return id;
}

function buildApiUrl(videoId) {
  const params = new URLSearchParams({
    legacy: 'true',
    embedder: 'https://www.dailymotion.com/id',
    referer: 'https://cse.knospe.co',
    geo: '1',
    'player-id': 'x138o4',
    enableAds: '0',
    locale: 'en-US',
    dmV1st: generateUUID(),
    dmTs: Date.now().toString().slice(0, 6),
    is_native_app: '0',
    app: 'com.dailymotion.neon',
    client_type: 'webapp',
    dmViewId: generateViewId(),
    parallelCalls: '1'
  });

  return `https://geo.dailymotion.com/video/${videoId}.json?${params.toString()}`;
}

async function DailyMotionDownloader(apiUrl) {
  try {
    const response = await fetchUrl(apiUrl);
    
    if (!response.ok) {
      throw new Error(`yahh error benerin sendiri`);
    }

    const data = JSON.parse(response.data);

    const subtitles = await fetchSubtitles(data.subtitles?.data || null);

    const videoInfo = {
      id: data.id,
      title: data.title,
      duration: data.duration,
      created_time: data.created_time,
      url: data.url,
      video_url: data.qualities?.auto?.[0]?.url || null,
      thumbnails: data.thumbnails,
      first_frames: data.first_frames,
      owner: {
        username: data.owner?.username,
        screenname: data.owner?.screenname,
        url: data.owner?.url
      },
      tags: data.tags,
      channel: data.channel,
      language: data.language,
      aspect_ratio: data.aspect_ratio,
      stream_formats: data.stream_formats,
      subtitles: subtitles
    };

    return {
      success: true,
      data: videoInfo
    };

  } catch (error) {
    return {
      success: false,
      error: error.message
    };
  }
}

async function main(videoUrl) {
  const videoId = extractVideoId(videoUrl);
  if (!videoId) {
    return { success: false, error: "video id nya gada bang" };
  }

  const apiUrl = buildApiUrl(videoId);
  const result = await DailyMotionDownloader(apiUrl);

  if (!result.success) {
    return { success: false, error: result.error };
  }

  return {
    success: true,
    data: result.data
  };
}

main("https://www.dailymotion.com/video/x9vak0w").then(res => {
  console.log(JSON.stringify(res, null, 2));
});