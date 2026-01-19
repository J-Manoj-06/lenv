/**
 * Daily Challenge Worker
 * 
 * Scheduled Cloudflare Worker that runs daily at 2:00 AM (Asia/Kolkata timezone)
 * Fetches daily challenge questions from OpenTriviaDB API based on difficulty levels
 * Stores results in Firestore daily_challenges collection
 * 
 * Difficulty Mapping:
 * - Grades 4-6: Easy questions
 * - Grades 7-10: Medium questions  
 * - Grades 11-12: Hard questions
 * 
 * Benefits:
 * - No API rate limits on student devices
 * - Consistent questions: All students in same grade see the same question
 * - Pre-cached for instant loading
 * - No Firebase Functions subscription needed
 * - Runs automatically every day
 */

interface DailyChallenge {
  date: string; // YYYY-MM-DD
  questions: {
    easy: QuestionData;
    medium: QuestionData;
    hard: QuestionData;
  };
  fetchedAt: string; // ISO timestamp
}

interface QuestionData {
  question: string;
  correctAnswer: string;
  incorrectAnswers: string[];
  options: string[]; // Shuffled options
  category: string;
  difficulty: string;
}

interface OpenTriviaResponse {
  response_code: number;
  results: Array<{
    category: string;
    type: string;
    difficulty: string;
    question: string;
    correct_answer: string;
    incorrect_answers: string[];
  }>;
}

// Category IDs based on OpenTriviaDB
const CATEGORIES = {
  easy: [9, 17, 22], // General Knowledge, Science & Nature, Geography
  medium: [17, 18, 19, 22, 23], // Science, Computers, Math, Geography, History
  hard: [17, 18, 19, 23, 24, 25], // Science, Computers, Math, History, Politics, Art
};

// Decode HTML entities from OpenTriviaDB responses
function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&apos;/g, "'")
    .replace(/&rsquo;/g, "'")
    .replace(/&ldquo;/g, '"')
    .replace(/&rdquo;/g, '"')
    .replace(/&hellip;/g, '...')
    .replace(/&ndash;/g, '–')
    .replace(/&mdash;/g, '—');
}

// Shuffle array using Fisher-Yates algorithm with date-based seed
function shuffleArray<T>(array: T[], seed: number): T[] {
  const shuffled = [...array];
  let currentIndex = shuffled.length;
  let randomValue: number;

  // Simple seeded random function
  const seededRandom = (s: number) => {
    const x = Math.sin(s++) * 10000;
    return x - Math.floor(x);
  };

  while (currentIndex !== 0) {
    randomValue = Math.floor(seededRandom(seed++) * currentIndex);
    currentIndex--;
    [shuffled[currentIndex], shuffled[randomValue]] = [
      shuffled[randomValue],
      shuffled[currentIndex],
    ];
  }

  return shuffled;
}

// Fetch question from OpenTriviaDB API
async function fetchQuestionFromAPI(
  difficulty: 'easy' | 'medium' | 'hard',
  seed: number
): Promise<QuestionData | null> {
  const categories = CATEGORIES[difficulty];
  
  // Try multiple categories and fall back to any difficulty if needed
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const categoryIndex = Math.floor(seededRandom(seed + attempt) * categories.length);
      const category = categories[categoryIndex];
      
      // First 3 attempts: request specific difficulty
      // Last 2 attempts: accept any difficulty from that category
      const useDifficultyFilter = attempt < 3;
      const url = useDifficultyFilter
        ? `https://opentdb.com/api.php?amount=1&type=multiple&category=${category}&difficulty=${difficulty}`
        : `https://opentdb.com/api.php?amount=1&type=multiple&category=${category}`;

      console.log(`Attempt ${attempt + 1}: Fetching ${difficulty} question from category ${category}${useDifficultyFilter ? '' : ' (any difficulty)'}...`);

      const response = await fetch(url, {
        headers: {
          'User-Agent': 'LenV-Edu/1.0 (Daily Challenge Worker)',
        },
      });

      if (!response.ok) {
        console.error(`OpenTriviaDB API error: ${response.status}`);
        await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1s before retry
        continue;
      }

      const data = (await response.json()) as OpenTriviaResponse;

      if (data.response_code !== 0 || !data.results || data.results.length === 0) {
        console.error(`Invalid response from OpenTriviaDB: ${data.response_code} (code 1 = no questions available)`);
        await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1s before retry
        continue;
      }

      const result = data.results[0];

      // Decode HTML entities
      const question = decodeHtmlEntities(result.question);
      const correctAnswer = decodeHtmlEntities(result.correct_answer);
      const incorrectAnswers = result.incorrect_answers.map((ans) =>
        decodeHtmlEntities(ans)
      );

      // Shuffle options with date-based seed for consistency
      const allOptions = [correctAnswer, ...incorrectAnswers];
      const shuffledOptions = shuffleArray(allOptions, seed + 1000);

      console.log(`✅ Successfully fetched ${result.difficulty} question from ${result.category}`);

      return {
        question,
        correctAnswer,
        incorrectAnswers,
        options: shuffledOptions,
        category: result.category,
        difficulty: result.difficulty,
      };
    } catch (error) {
      console.error(`Attempt ${attempt + 1} failed for ${difficulty} question:`, error);
      await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1s before retry
    }
  }
  
  console.error(`❌ Failed to fetch ${difficulty} question after 5 attempts`);
  return null;
}

// Simple seeded random helper
function seededRandom(seed: number): number {
  const x = Math.sin(seed) * 10000;
  return x - Math.floor(x);
}

// Get JWT token for Firebase authentication
async function getFirebaseToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const expiry = now + 3600; // Token valid for 1 hour

  const header = {
    alg: 'RS256',
    typ: 'JWT',
  };

  const claimSet = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: 'https://firestore.googleapis.com/',
    iat: now,
    exp: expiry,
  };

  const headerBase64 = btoa(JSON.stringify(header));
  const claimSetBase64 = btoa(JSON.stringify(claimSet));
  const message = `${headerBase64}.${claimSetBase64}`;

  // Import private key
  const privateKeyPem = serviceAccount.private_key
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\n/g, '')
    .replace(/\s/g, '');
  
  // Base64 decode the PEM string
  const binaryDerString = atob(privateKeyPem);
  const binaryDer = new Uint8Array(binaryDerString.length);
  for (let i = 0; i < binaryDerString.length; i++) {
    binaryDer[i] = binaryDerString.charCodeAt(i);
  }
  
  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer.buffer,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign']
  );

  // Sign the message
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(message)
  );

  const signatureBase64 = btoa(
    String.fromCharCode(...new Uint8Array(signature))
  );

  return `${message}.${signatureBase64}`;
}

// Store daily challenges in Firestore
async function storeDailyChallenges(
  challenge: DailyChallenge,
  serviceAccount: any
): Promise<void> {
  const projectId = serviceAccount.project_id;
  const firestoreUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/daily_challenges/${challenge.date}`;

  // Get JWT token
  const token = await getFirebaseToken(serviceAccount);

  // Convert to Firestore format
  const firestoreDoc = {
    fields: {
      date: { stringValue: challenge.date },
      fetchedAt: { stringValue: challenge.fetchedAt },
      // Easy questions (Grades 4-6)
      easy_question: { stringValue: challenge.questions.easy.question },
      easy_correctAnswer: { stringValue: challenge.questions.easy.correctAnswer },
      easy_options: {
        arrayValue: {
          values: challenge.questions.easy.options.map((opt) => ({
            stringValue: opt,
          })),
        },
      },
      easy_category: { stringValue: challenge.questions.easy.category },
      easy_difficulty: { stringValue: challenge.questions.easy.difficulty },
      // Medium questions (Grades 7-10)
      medium_question: { stringValue: challenge.questions.medium.question },
      medium_correctAnswer: {
        stringValue: challenge.questions.medium.correctAnswer,
      },
      medium_options: {
        arrayValue: {
          values: challenge.questions.medium.options.map((opt) => ({
            stringValue: opt,
          })),
        },
      },
      medium_category: { stringValue: challenge.questions.medium.category },
      medium_difficulty: { stringValue: challenge.questions.medium.difficulty },
      // Hard questions (Grades 11-12)
      hard_question: { stringValue: challenge.questions.hard.question },
      hard_correctAnswer: { stringValue: challenge.questions.hard.correctAnswer },
      hard_options: {
        arrayValue: {
          values: challenge.questions.hard.options.map((opt) => ({
            stringValue: opt,
          })),
        },
      },
      hard_category: { stringValue: challenge.questions.hard.category },
      hard_difficulty: { stringValue: challenge.questions.hard.difficulty },
    },
  };

  const response = await fetch(firestoreUrl, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(firestoreDoc),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Firestore error: ${response.status} - ${errorText}`);
  }

  console.log('✅ Daily challenges stored in Firestore successfully!');
}

// Main scheduled handler
export default {
  async scheduled(
    event: ScheduledEvent,
    env: {
      FIREBASE_SERVICE_ACCOUNT: string;
    },
    ctx: ExecutionContext
  ): Promise<void> {
    console.log('Daily challenge fetch triggered at:', new Date().toISOString());

    try {
      // Parse service account from environment
      const serviceAccount = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
      const projectId = serviceAccount.project_id;

      // Get today's date in Asia/Kolkata timezone
      const now = new Date();
      const indiaTime = new Date(
        now.toLocaleString('en-US', { timeZone: 'Asia/Kolkata' })
      );
      const today = indiaTime.toISOString().split('T')[0];

      console.log(`Fetching daily challenges for ${today}...`);

      // Check if challenges already exist for today
      const checkUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/daily_challenges/${today}`;
      const token = await getFirebaseToken(serviceAccount);

      const existingDoc = await fetch(checkUrl, {
        headers: { Authorization: `Bearer ${token}` },
      });

      if (existingDoc.ok) {
        console.log(`Daily challenges for ${today} already exist. Skipping fetch.`);
        return;
      }

      // Fetch questions for each difficulty level
      const seed = parseInt(today.replace(/-/g, '')); // Use date as seed for consistency

      console.log('Fetching easy question (Grades 4-6)...');
      const easyQuestion = await fetchQuestionFromAPI('easy', seed);
      if (!easyQuestion) {
        throw new Error('Failed to fetch easy question');
      }

      console.log('Fetching medium question (Grades 7-10)...');
      const mediumQuestion = await fetchQuestionFromAPI('medium', seed + 100);
      if (!mediumQuestion) {
        throw new Error('Failed to fetch medium question');
      }

      console.log('Fetching hard question (Grades 11-12)...');
      const hardQuestion = await fetchQuestionFromAPI('hard', seed + 200);
      if (!hardQuestion) {
        throw new Error('Failed to fetch hard question');
      }

      // Create daily challenge object
      const challenge: DailyChallenge = {
        date: today,
        questions: {
          easy: easyQuestion,
          medium: mediumQuestion,
          hard: hardQuestion,
        },
        fetchedAt: new Date().toISOString(),
      };

      // Store in Firestore
      await storeDailyChallenges(challenge, serviceAccount);

      console.log(`✅ Daily challenges for ${today} stored successfully!`);
      console.log('  - Easy:', easyQuestion.question.substring(0, 50) + '...');
      console.log('  - Medium:', mediumQuestion.question.substring(0, 50) + '...');
      console.log('  - Hard:', hardQuestion.question.substring(0, 50) + '...');
    } catch (error) {
      console.error('❌ Failed to fetch/store daily challenges:', error);
      throw error;
    }
  },

  async fetch(request: Request, env: any): Promise<Response> {
    // Manual trigger endpoint for testing
    if (request.method === 'POST') {
      try {
        await this.scheduled({} as ScheduledEvent, env, {} as ExecutionContext);
        return new Response('Daily challenges fetched and stored successfully!', {
          status: 200,
        });
      } catch (error) {
        return new Response(`Error: ${error}`, { status: 500 });
      }
    }

    return new Response('Use POST to manually trigger daily challenge fetch', {
      status: 405,
    });
  },
};
