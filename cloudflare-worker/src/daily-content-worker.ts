/**
 * Daily Content Prefetch Worker
 * 
 * Scheduled Cloudflare Worker that runs daily at 2:00 AM (Asia/Kolkata timezone)
 * Fetches daily content (quote, fact, history) from external APIs once per day
 * Stores results in Firestore daily_content collection
 * 
 * Benefits:
 * - Reduces API calls from N students to 1 call per day
 * - Cost savings: ~98% reduction in external API usage
 * - Better reliability: Fallback content if APIs fail
 * - Consistent data: All students see the same daily content
 */

interface Env {
  FIREBASE_SERVICE_ACCOUNT: string; // JSON string with Firebase service account credentials
}

interface DailyContent {
  date: string; // YYYY-MM-DD
  quote: {
    text: string;
    author: string;
    source: string;
  };
  fact: {
    text: string;
    source: string;
  };
  history: {
    events: Array<{
      text: string;
      year: string;
      title: string;
      thumb: string;
      category: string;
    }>;
    source: string;
  };
  fetchedAt: string; // ISO timestamp
  status: 'success' | 'partial' | 'failed';
  errors?: string[];
}

// Fallback content when APIs fail
const FALLBACK_QUOTES = [
  { text: 'Success is not final, failure is not fatal: it is the courage to continue that counts.', author: 'Winston Churchill' },
  { text: 'Believe you can and you\'re halfway there.', author: 'Theodore Roosevelt' },
  { text: 'The only way to do great work is to love what you do.', author: 'Steve Jobs' },
  { text: 'Education is the most powerful weapon which you can use to change the world.', author: 'Nelson Mandela' },
  { text: 'The future belongs to those who believe in the beauty of their dreams.', author: 'Eleanor Roosevelt' },
];

const FALLBACK_FACTS = [
  'The Eiffel Tower can be 15 cm taller during hot days due to thermal expansion.',
  'Octopuses have three hearts and blue blood.',
  'Bananas are berries, but strawberries are not.',
  'Honeybees can recognize human faces.',
  'A day on Venus is longer than its year.',
  'The human brain uses about 20% of the body\'s energy despite being only 2% of body mass.',
  'There are more stars in the universe than grains of sand on all Earth\'s beaches.',
];

// Fetch daily quote from ZenQuotes API
async function fetchQuote(): Promise<{ text: string; author: string; source: string }> {
  try {
    const response = await fetch('https://zenquotes.io/api/today', {
      headers: { 'Accept': 'application/json' },
      signal: AbortSignal.timeout(10000), // 10s timeout
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const data = await response.json() as any[];
    if (!Array.isArray(data) || data.length === 0) {
      throw new Error('Unexpected response format');
    }

    const item = data[0];
    return {
      text: (item.q || '').toString(),
      author: (item.a || 'Unknown').toString(),
      source: 'zenquotes.io',
    };
  } catch (error) {
    console.error('Failed to fetch quote:', error);
    // Return random fallback
    const fallback = FALLBACK_QUOTES[Math.floor(Math.random() * FALLBACK_QUOTES.length)];
    return { ...fallback, source: 'fallback' };
  }
}

// Fetch daily fact from Useless Facts API
async function fetchFact(): Promise<{ text: string; source: string }> {
  try {
    const response = await fetch('https://uselessfacts.jsph.pl/random.json?language=en', {
      headers: { 'Accept': 'application/json' },
      signal: AbortSignal.timeout(10000),
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const data = await response.json() as any;
    if (!data || !data.text) {
      throw new Error('Unexpected response format');
    }

    return {
      text: data.text.toString(),
      source: 'uselessfacts.jsph.pl',
    };
  } catch (error) {
    console.error('Failed to fetch fact:', error);
    // Return random fallback
    const fallback = FALLBACK_FACTS[Math.floor(Math.random() * FALLBACK_FACTS.length)];
    return { text: fallback, source: 'fallback' };
  }
}

// Fetch today's history from Wikimedia API
async function fetchHistory(): Promise<{
  events: Array<{
    text: string;
    year: string;
    title: string;
    thumb: string;
    category: string;
  }>;
  source: string;
}> {
  try {
    const now = new Date();
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const dd = String(now.getDate()).padStart(2, '0');

    const response = await fetch(
      `https://api.wikimedia.org/feed/v1/wikipedia/en/onthisday/all/${mm}/${dd}`,
      {
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'LenV-Edu/1.0 (Daily Content Worker)',
        },
        signal: AbortSignal.timeout(15000),
      }
    );

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const data = await response.json() as any;

    const extractEvents = (arr: any[], category: string) => {
      if (!Array.isArray(arr)) return [];
      return arr.slice(0, 8).map((e: any) => {
        let title = '';
        let thumb = '';
        if (Array.isArray(e.pages) && e.pages.length > 0) {
          const p0 = e.pages[0];
          title = p0.titles?.display || p0.title || '';
          thumb = p0.thumbnail?.source || '';
        }
        return {
          text: (e.text || '').toString(),
          year: (e.year || '').toString(),
          title,
          thumb,
          category,
        };
      }).filter(m => m.text);
    };

    const events = [
      ...extractEvents(data.selected || [], 'Selected'),
      ...extractEvents(data.events || [], 'Event'),
    ];

    if (events.length === 0) {
      throw new Error('No events found');
    }

    return {
      events,
      source: 'api.wikimedia.org',
    };
  } catch (error) {
    console.error('Failed to fetch history:', error);
    // Return minimal fallback
    return {
      events: [{
        text: 'Historical events are currently unavailable. Please try again later.',
        year: new Date().getFullYear().toString(),
        title: 'Service Unavailable',
        thumb: '',
        category: 'System',
      }],
      source: 'fallback',
    };
  }
}

// Get Firebase access token from service account
async function getFirebaseAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/datastore',
  };

  // Create JWT header and payload
  const header = { alg: 'RS256', typ: 'JWT' };
  const encodedHeader = btoa(JSON.stringify(header)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
  const encodedPayload = btoa(JSON.stringify(payload)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

  // Sign with private key (requires Web Crypto API)
  const privateKey = serviceAccount.private_key;
  const algorithm = { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' };
  
  const keyData = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(privateKey),
    algorithm,
    false,
    ['sign']
  );

  const signature = await crypto.subtle.sign(
    algorithm,
    keyData,
    new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`)
  );

  const encodedSignature = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');

  const jwt = `${encodedHeader}.${encodedPayload}.${encodedSignature}`;

  // Exchange JWT for access token
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  if (!tokenResponse.ok) {
    throw new Error(`Failed to get access token: ${tokenResponse.status}`);
  }

  const tokenData = await tokenResponse.json() as any;
  return tokenData.access_token;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const pemContents = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');
  const binaryString = atob(pemContents);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes.buffer;
}

// Store daily content in Firestore
async function storeDailyContent(content: DailyContent, serviceAccount: any): Promise<void> {
  const accessToken = await getFirebaseAccessToken(serviceAccount);
  const projectId = serviceAccount.project_id;
  
  const firestoreUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/daily_content/${content.date}`;

  const firestoreDoc = {
    fields: {
      date: { stringValue: content.date },
      quote: {
        mapValue: {
          fields: {
            text: { stringValue: content.quote.text },
            author: { stringValue: content.quote.author },
            source: { stringValue: content.quote.source },
          },
        },
      },
      fact: {
        mapValue: {
          fields: {
            text: { stringValue: content.fact.text },
            source: { stringValue: content.fact.source },
          },
        },
      },
      history: {
        mapValue: {
          fields: {
            events: {
              arrayValue: {
                values: content.history.events.map(e => ({
                  mapValue: {
                    fields: {
                      text: { stringValue: e.text },
                      year: { stringValue: e.year },
                      title: { stringValue: e.title },
                      thumb: { stringValue: e.thumb },
                      category: { stringValue: e.category },
                    },
                  },
                })),
              },
            },
            source: { stringValue: content.history.source },
          },
        },
      },
      fetchedAt: { stringValue: content.fetchedAt },
      status: { stringValue: content.status },
      errors: content.errors
        ? { arrayValue: { values: content.errors.map(e => ({ stringValue: e })) } }
        : { nullValue: null },
    },
  };

  const response = await fetch(firestoreUrl, {
    method: 'PATCH',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(firestoreDoc),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Failed to store in Firestore: ${response.status} - ${errorText}`);
  }
}

// Main scheduled handler
export default {
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    console.log('Daily content fetch triggered at:', new Date().toISOString());

    try {
      // Parse service account credentials
      const serviceAccount = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);

      // Get today's date in YYYY-MM-DD format (Asia/Kolkata timezone)
      const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });

      // Check if today's content already exists (prevent duplicate fetches)
      const projectId = serviceAccount.project_id;
      const accessToken = await getFirebaseAccessToken(serviceAccount);
      const checkUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/daily_content/${today}`;
      
      const checkResponse = await fetch(checkUrl, {
        headers: { 'Authorization': `Bearer ${accessToken}` },
      });

      if (checkResponse.ok) {
        console.log(`Content for ${today} already exists. Skipping fetch.`);
        return;
      }

      // Fetch all content in parallel
      console.log('Fetching daily content from external APIs...');
      const [quote, fact, history] = await Promise.all([
        fetchQuote(),
        fetchFact(),
        fetchHistory(),
      ]);

      // Determine overall status
      const errors: string[] = [];
      let status: 'success' | 'partial' | 'failed' = 'success';

      if (quote.source === 'fallback') {
        errors.push('Quote API failed, using fallback');
        status = 'partial';
      }
      if (fact.source === 'fallback') {
        errors.push('Fact API failed, using fallback');
        status = 'partial';
      }
      if (history.source === 'fallback') {
        errors.push('History API failed, using fallback');
        status = 'partial';
      }

      const content: DailyContent = {
        date: today,
        quote,
        fact,
        history,
        fetchedAt: new Date().toISOString(),
        status,
        errors: errors.length > 0 ? errors : undefined,
      };

      // Store in Firestore
      console.log('Storing content in Firestore...');
      await storeDailyContent(content, serviceAccount);

      console.log(`✅ Daily content for ${today} stored successfully!`);
      console.log('Status:', status);
      if (errors.length > 0) {
        console.log('Warnings:', errors);
      }
    } catch (error) {
      console.error('❌ Failed to fetch/store daily content:', error);
      throw error; // Cloudflare will retry on failure
    }
  },

  // Optional: HTTP endpoint for manual testing
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== 'POST') {
      return new Response('Use POST to manually trigger daily content fetch', { status: 405 });
    }

    try {
      // Manually trigger the scheduled function
      await this.scheduled(null as any, env, null as any);
      return new Response('Daily content fetch completed successfully', { status: 200 });
    } catch (error: any) {
      return new Response(`Error: ${error.message}`, { status: 500 });
    }
  },
};
