mkdir -p ~/Desktop/wtn-video-blog/src/lib ~/Desktop/wtn-video-blog/src/layouts ~/Desktop/wtn-video-blog/src/pages/posts && cd ~/Desktop/wtn-video-blog

cat << 'EOF' > package.json
{
  "name": "wtn-video-blog",
  "type": "module",
  "version": "1.0.0",
  "scripts": {
    "dev": "astro dev",
    "build": "astro build",
    "preview": "astro preview"
  },
  "dependencies": {
    "@notionhq/client": "^2.2.15",
    "astro": "^4.15.0"
  }
}
EOF

cat << 'EOF' > astro.config.mjs
import { defineConfig } from 'astro/config';
export default defineConfig({
  site: 'https://blog.wtnsourcing.com'
});
EOF

cat << 'EOF' > src/lib/notion.js
import { Client } from '@notionhq/client';

const notion = new Client({
  auth: import.meta.env.NOTION_TOKEN || process.env.NOTION_TOKEN,
});

const DATABASE_ID = import.meta.env.NOTION_DATABASE_ID || process.env.NOTION_DATABASE_ID;

export function getYouTubeId(url) {
  if (!url) return '';
  const match = url.match(/(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?v=|watch\?.+&v=|shorts\/))([^&?\/]+)/);
  return match ? match[1] : '';
}

function richTextToHtml(richTextArray = []) {
  return richTextArray.map(t => {
    let content = t.plain_text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
    if (t.annotations?.bold) content = `<strong>${content}</strong>`;
    if (t.annotations?.italic) content = `<em>${content}</em>`;
    if (t.annotations?.underline) content = `<u>${content}</u>`;
    if (t.annotations?.strikethrough) content = `<s>${content}</s>`;
    if (t.annotations?.code) content = `<code>${content}</code>`;
    if (t.href) content = `<a href="${t.href}" target="_blank" rel="noopener">${content}</a>`;
    return content;
  }).join('');
}

export async function getPublishedPosts() {
  if (!DATABASE_ID) return [];
  const response = await notion.databases.query({
    database_id: DATABASE_ID,
    filter: {
      property: 'Published',
      checkbox: { equals: true },
    },
  });

  return response.results.map(page => {
    const props = page.properties;
    const title = props['Title']?.title?.[0]?.plain_text || 'Untitled';
    const rawSlug = props['Slug']?.rich_text?.[0]?.plain_text || '';
    const slug = rawSlug.trim() || page.id;
    const section = props['Section']?.select?.name || 'Knowledge Hub';
    const sectionPinned = props['Section Pinned']?.checkbox || false;
    const youtubeUrl = props['YouTube URL']?.url || '';
    const youtubeId = getYouTubeId(youtubeUrl);
    const summary = props['Summary']?.rich_text?.map(t => t.plain_text).join('') || '';
    const date = props['Date']?.date?.start || page.created_time.split('T')[0];

    return {
      id: page.id,
      title,
      slug,
      section,
      sectionPinned,
      youtubeUrl,
      youtubeId,
      summary,
      date,
    };
  });
}

export async function getPostBlocksHtml(blockId) {
  const blocks = [];
  let cursor = undefined;
  while (true) {
    const { results, next_cursor } = await notion.blocks.children.list({
      block_id: blockId,
      start_cursor: cursor,
    });
    blocks.push(...results);
    if (!next_cursor) break;
    cursor = next_cursor;
  }

  let html = '';
  let inBulletList = false;
  let inNumberedList = false;

  for (const b of blocks) {
    const type = b.type;
    if (type !== 'bulleted_list_item' && inBulletList) {
      html += '</ul>';
      inBulletList = false;
    }
    if (type !== 'numbered_list_item' && inNumberedList) {
      html += '</ol>';
      inNumberedList = false;
    }

    switch (type) {
      case 'paragraph': {
        const text = richTextToHtml(b.paragraph.rich_text);
        if (text) html += `<p>${text}</p>`;
        break;
      }
      case 'heading_1':
        html += `<h2>${richTextToHtml(b.heading_1.rich_text)}</h2>`;
        break;
      case 'heading_2':
        html += `<h2>${richTextToHtml(b.heading_2.rich_text)}</h2>`;
        break;
      case 'heading_3':
        html += `<h3>${richTextToHtml(b.heading_3.rich_text)}</h3>`;
        break;
      case 'bulleted_list_item':
        if (!inBulletList) { html += '<ul>'; inBulletList = true; }
        html += `<li>${richTextToHtml(b.bulleted_list_item.rich_text)}</li>`;
        break;
      case 'numbered_list_item':
        if (!inNumberedList) { html += '<ol>'; inNumberedList = true; }
        html += `<li>${richTextToHtml(b.numbered_list_item.rich_text)}</li>`;
        break;
      case 'quote':
        html += `<blockquote>${richTextToHtml(b.quote.rich_text)}</blockquote>`;
        break;
      case 'callout':
        html += `<div class="callout-box">${richTextToHtml(b.callout.rich_text)}</div>`;
        break;
      case 'divider':
        html += `<hr class="content-divider" />`;
        break;
      case 'image': {
        const imgUrl = b.image.type === 'external' ? b.image.external.url : b.image.file.url;
        const caption = richTextToHtml(b.image.caption);
        html += `<figure class="post-image"><img src="${imgUrl}" alt="${caption || 'WTN Sourcing Image'}" loading="lazy" />${caption ? `<figcaption>${caption}</figcaption>` : ''}</figure>`;
        break;
      }
      case 'video': {
        const vUrl = b.video.type === 'external' ? b.video.external.url : b.video.file.url;
        const ytId = getYouTubeId(vUrl);
        if (ytId) {
          html += `<div class="post-video-frame"><iframe src="https://www.youtube-nocookie.com/embed/${ytId}?rel=0" allowfullscreen loading="lazy"></iframe></div>`;
        } else {
          html += `<div class="post-video-frame"><video src="${vUrl}" controls playsinline></video></div>`;
        }
        break;
      }
      case 'audio': {
        const aUrl = b.audio.type === 'external' ? b.audio.external.url : b.audio.file.url;
        html += `<div class="post-audio"><audio src="${aUrl}" controls style="width:100%"></audio></div>`;
        break;
      }
      case 'embed': {
        const eUrl = b.embed.url;
        const ytId = getYouTubeId(eUrl);
        if (ytId) {
          html += `<div class="post-video-frame"><iframe src="https://www.youtube-nocookie.com/embed/${ytId}?rel=0" allowfullscreen loading="lazy"></iframe></div>`;
        } else {
          html += `<div class="post-embed"><iframe src="${eUrl}" style="width:100%;min-height:180px;border:0;border-radius:1rem;" loading="lazy"></iframe></div>`;
        }
        break;
      }
    }
  }
  if (inBulletList) html += '</ul>';
  if (inNumberedList) html += '</ol>';
  return html;
}
EOF

cat << 'EOF' > src/layouts/BaseLayout.astro
---
const {
  title = "WTN Sourcing | Video Insights & Ground Case Studies",
  description = "Live factory audits, factory production, packaging structural testing, and QC walkthroughs direct from China manufacturing hubs.",
  ogImage = "https://blog.wtnsourcing.com/assets/images/share.jpg"
} = Astro.props;
---
<!DOCTYPE HTML>
<html lang="en">
<head>
  <title>{title}</title>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <meta name="description" content={description} />
  <meta property="og:site_name" content="WTN Sourcing | Video Insights & Ground Case Studies" />
  <meta property="og:title" content={title} />
  <meta property="og:type" content="article" />
  <meta property="og:description" content={description} />
  <meta property="og:image" content={ogImage} />
  <meta property="twitter:card" content="summary_large_image" />
  <link href="https://fonts.googleapis.com/css2?display=swap&family=Pacifico:ital,wght@0,400;1,400&family=Instrument+Sans:ital,wght@0,500;0,700;1,500;1,700&family=Inter:ital,wght@0,400;0,700;1,400;1,700" rel="stylesheet" type="text/css" />
  <style is:global>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    html { font-size: 13pt; scroll-behavior: smooth; }
    body {
      background-color: #FFFFFF;
      background-image: linear-gradient(0deg, #FFFFFF 63%, #E9EEF5 100%);
      background-attachment: fixed;
      color: rgba(22, 39, 60, 0.6);
      font-family: 'Inter', sans-serif;
      line-height: 1.875;
      overflow-x: hidden;
    }
    a { color: inherit; transition: color 0.25s ease; }

    /* Top Flat Navigation */
    .top-nav-bar {
      width: 100%;
      background: rgba(255, 255, 255, 0.92);
      backdrop-filter: blur(10px);
      border-bottom: 1px solid rgba(22, 39, 60, 0.08);
      position: sticky;
      top: 0;
      z-index: 1000;
    }
    .top-nav-inner {
      max-width: 68rem;
      margin: 0 auto;
      padding: 1rem 2rem;
      display: flex;
      align-items: center;
      justify-content: space-between;
      flex-wrap: wrap;
      gap: 1rem;
    }
    .nav-brand {
      font-family: 'Instrument Sans', sans-serif;
      font-weight: 700;
      font-size: 1.15rem;
      color: #0DA5DB;
      text-decoration: none;
    }
    .nav-links {
      display: flex;
      align-items: center;
      flex-wrap: wrap;
      gap: 0.75rem;
      font-size: 0.9rem;
      font-family: 'Instrument Sans', sans-serif;
      font-weight: 500;
    }
    .nav-links a {
      color: #16273C;
      text-decoration: none;
    }
    .nav-links a:hover {
      color: #0DA5DB;
    }
    .nav-sep {
      color: rgba(22, 39, 60, 0.25);
    }

    /* Main Container */
    .site-container {
      max-width: 64rem;
      margin: 0 auto;
      padding: 0 2.5rem 6rem 2.5rem;
    }

    /* Full Screen Gradient Container (Style-4) */
    .gradient-full-section {
      width: 100vw;
      position: relative;
      left: 50%;
      margin-left: -50vw;
      background-image: linear-gradient(146deg, #33C4B4 0%, #0DA5DB 100%);
      padding: 5.5rem 2.5rem;
      color: #FFFFFF;
    }
    .gradient-inner {
      max-width: 60rem;
      margin: 0 auto;
    }
    .text-style-1 {
      font-family: 'Pacifico', cursive;
      font-size: 1.75em;
      line-height: 1.625;
      font-weight: 400;
      background-image: linear-gradient(226deg, #CCF2FF 85%, #FFFFFF 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      margin-bottom: 1.25rem;
    }
    .text-style-4 {
      font-family: 'Instrument Sans', sans-serif;
      letter-spacing: -0.08rem;
      font-size: 3.25em;
      line-height: 1.15;
      font-weight: 500;
      color: #FFFFFF;
      margin-bottom: 1.5rem;
    }
    .text-style-9 {
      font-family: 'Instrument Sans', sans-serif;
      letter-spacing: -0.025rem;
      font-size: 2.5em;
      line-height: 1.25;
      font-weight: 500;
      color: #FFFFFF;
      margin-bottom: 1.5rem;
    }
    .text-style-10 {
      color: rgba(255, 255, 255, 0.85);
      font-family: 'Inter', sans-serif;
      font-size: 1.05em;
      line-height: 1.875;
    }
    .text-style-10 strong { color: #FFFFFF; }

    /* Pill Buttons (Style-2) */
    .pill-button {
      display: inline-flex;
      align-items: center;
      height: 3.25rem;
      padding: 0 1.625rem;
      font-family: 'Instrument Sans', sans-serif;
      font-size: 1em;
      font-weight: 500;
      border-radius: 3rem;
      box-shadow: 0rem 0.625rem 1.625rem 0rem rgba(22, 39, 60, 0.08);
      background-color: #FFFFFF;
      color: #1AAFCB;
      background-image: linear-gradient(227deg, #DEFAFF 0%, rgba(255,255,255,0.012) 100%);
      text-decoration: none;
      margin-top: 2rem;
      transition: transform 0.25s ease, background-color 0.25s ease;
    }
    .pill-button:hover {
      transform: scale(1.05);
      background-color: rgba(255, 255, 255, 0.94);
    }
    .pill-button svg {
      width: 1.25em;
      height: 1.25em;
      fill: #1AAFCB;
      margin-left: 1rem;
    }

    /* Section Dividers & Headings */
    .divider-short {
      width: 3rem;
      height: 8px;
      border-radius: 30px;
      background-color: #33C4B4;
      background-image: linear-gradient(270deg, #0DA5DB 0%, rgba(51,196,180,0.012) 100%);
      border: 0;
      margin: 5rem 0 2rem 0;
    }
    .divider-full {
      width: 100vw;
      position: relative;
      left: 50%;
      margin-left: -50vw;
      height: 2px;
      background-color: rgba(22, 39, 60, 0.071);
      border: 0;
      margin-top: 6rem;
    }
    .text-style-8 {
      font-family: 'Instrument Sans', sans-serif;
      letter-spacing: -0.025rem;
      font-size: 2.5em;
      line-height: 1.25;
      font-weight: 500;
      background-image: linear-gradient(215deg, #0DA5DB 60%, #33C4B4 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      margin-bottom: 1rem;
    }
    .text-style-6 {
      color: #0DA5DB;
      font-family: 'Instrument Sans', sans-serif;
      font-size: 1.5em;
      line-height: 1.3;
      font-weight: 500;
      margin-bottom: 1rem;
    }
    .text-style-3 {
      color: rgba(22, 39, 60, 0.65);
      font-family: 'Inter', sans-serif;
      font-size: 1em;
      line-height: 1.875;
    }

    /* Alternating 2-Column Video Rows */
    .video-stream {
      display: flex;
      flex-direction: column;
      gap: 6rem;
      margin-top: 3.5rem;
    }
    .video-card-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 4rem;
    }
    .video-card-row.reverse {
      flex-direction: row-reverse;
    }
    .card-text-col, .card-video-col {
      flex: 1;
      width: 50%;
    }
    .pinned-badge {
      display: inline-block;
      font-family: 'Instrument Sans', sans-serif;
      font-size: 0.75rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.06rem;
      color: #FFFFFF;
      background: linear-gradient(146deg, #33C4B4 0%, #0DA5DB 100%);
      padding: 0.25rem 0.75rem;
      border-radius: 2rem;
      margin-bottom: 0.75rem;
    }
    .video-box {
      width: 100%;
      aspect-ratio: 16 / 9;
      border-radius: 1.25rem;
      border: 5px solid #FFFFFF;
      box-shadow: 0rem 1.75rem 2.375rem 0rem rgba(22, 39, 60, 0.09);
      overflow: hidden;
      background: #000;
    }
    .video-box iframe {
      width: 100%;
      height: 100%;
      border: 0;
    }

    /* CTA 2-Columns */
    .cta-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 5rem;
      align-items: center;
    }
    .cta-col-right {
      border-left: 1px solid rgba(255, 255, 255, 0.412);
      padding-left: 5rem;
    }

    /* Footer (Style-7) */
    .footer-text {
      margin-top: 5rem;
      color: rgba(22, 39, 60, 0.6);
      font-family: 'Inter', sans-serif;
      font-size: 0.95em;
      line-height: 1.95;
    }
    .footer-text a {
      color: #38B5A7;
      text-decoration: underline;
    }
    .footer-text a:hover {
      text-decoration: none;
    }

    @media (max-width: 768px) {
      html { font-size: 11.5pt; }
      .video-card-row, .video-card-row.reverse {
        flex-direction: column-reverse;
        gap: 2rem;
      }
      .card-text-col, .card-video-col { width: 100%; }
      .cta-grid { grid-template-columns: 1fr; gap: 3rem; }
      .cta-col-right {
        border-left: 0;
        border-top: 1px solid rgba(255, 255, 255, 0.412);
        padding-left: 0;
        padding-top: 3rem;
      }
    }
  </style>
</head>
<body>
  <svg xmlns="http://www.w3.org/2000/svg" display="none">
    <symbol id="icon-arrow-right" viewBox="0 0 40 40">
      <path d="M34.1,19.9c0,0.3-0.1,0.3-0.1,0.4L21.3,33.1c-0.1,0.1-0.1,0.1-0.4,0.1c-0.3,0-0.3-0.1-0.4-0.1L19,31.6 c-0.1-0.1-0.1-0.1-0.1-0.4s0.1-0.3,0.1-0.4l9.2-9.2H5.8c-0.1,0-0.2,0-0.2,0c0,0,0,0,0,0c-0.1-0.1-0.1-0.2-0.1-0.4v-2.5 c0-0.2,0.1-0.4,0.1-0.5c0,0,0.1,0,0.2,0h22.4L19,9c-0.1-0.1-0.1-0.1-0.1-0.4c0-0.3,0.1-0.3,0.1-0.4l1.5-1.5c0.1-0.1,0.1-0.1,0.4-0.1 c0.3,0,0.3,0.1,0.4,0.1L34,19.5C34,19.6,34.1,19.6,34.1,19.9z"/>
    </symbol>
  </svg>

  <!-- Flat Top Navigation Bar -->
  <header class="top-nav-bar">
    <div class="top-nav-inner">
      <a href="/" class="nav-brand">WTN Sourcing Blog</a>
      <nav class="nav-links">
        <a href="https://www.wtnsourcing.com">Home</a>
        <span class="nav-sep">|</span>
        <a href="https://sourcing.wtnsourcing.com">Product Sourcing</a>
        <span class="nav-sep">|</span>
        <a href="https://premium.wtnsourcing.com">Custom Packaging</a>
        <span class="nav-sep">|</span>
        <a href="https://kitting.wtnsourcing.com">Kitting &amp; Fulfillment</a>
        <span class="nav-sep">|</span>
        <a href="https://process.wtnsourcing.com">Our SOP</a>
      </nav>
    </div>
  </header>

  <main class="site-container">
    <slot />

    <!-- Bottom Zero-Risk Execution & Free Audit Container -->
    <section class="gradient-full-section" style="margin-top: 6rem;">
      <div class="gradient-inner cta-grid">
        <div>
          <h2 class="text-style-4">Zero-Risk Execution</h2>
          <p class="text-style-10">
            Partner with a team that operates directly <strong>on the ground in China</strong>. We protect your designs with strict China NNN agreements, conduct rigorous AQL inspections, and deliver fully kitted products to your door via DDP. No hidden fees, no customs delay.
          </p>
        </div>
        <div class="cta-col-right">
          <h2 class="text-style-9">Free Audit</h2>
          <p class="text-style-10">
            Send us your packaging dielines or Bill of Materials. Our engineering team will review your files for structural integrity and EU PPWR compliance at absolutely <strong>Zero Cost</strong>.
          </p>
          <a href="mailto:team@wtnsourcing.com?subject=DDP/FOB/EXW%20Quote%20Request" class="pill-button">
            <span>Contact Us via Email</span>
            <svg><use xlink:href="#icon-arrow-right"></use></svg>
          </a>
        </div>
      </div>
    </section>

    <!-- Footer -->
    <footer class="footer-text">
      <p>
        ©2026 WTN Sourcing. All rights reserved. Established in Hong Kong since 2023.<br />
        Working Time: 10:00-20:00 (Hong Kong) | 19:00-05:00 (Los Angeles) | 03:00-13:00 (London)<br />
        Operational Office: <a href="https://maps.app.goo.gl/cgcYgGnVmPagGaKs9" target="_blank">Qian Deng Lake Venture Capital Town, Foshan, Guangdong Province, China</a><br />
        WhatsApp: +86 166 0305 4221<br />
        Email: <a href="mailto:team@wtnsourcing.com">team@wtnsourcing.com</a><br />
        Terms: <a href="https://docs.google.com/document/d/192LkESCtXM-VY0LllAqtTrcqR8vDCsVGnl5_nd9IDbc/edit?usp=sharing" target="_blank">Privacy Policy</a> | <a href="https://docs.google.com/document/d/1-u9N-waPhQ9Rx-DRns_aRoKu4oR73dpBSnQfvkXR7wA/edit?usp=sharing" target="_blank">Term of Service</a> | <a href="https://docs.google.com/document/d/1n2i5AAJaPV8mVroQAS_Np5Rax6TPJfSjZ6dTdq_Z29A/edit?usp=share_link" target="_blank">Non-Disclosure Agreement</a> | <a href="https://docs.google.com/document/d/14KVDP4cTOoz7pBa8L_SOfwv0hphRVegssSf6uD5TOT8/edit?usp=sharing" target="_blank">NNN Agreement</a> | <a href="https://docs.google.com/document/d/12TH8KEFW3Cuy3Um9XtjOAnDgsp-pFK_uqlZZq23mA_Q/edit?usp=sharing" target="_blank">Special Power of Attorney</a> | <a href="https://drive.google.com/drive/folders/1s5HPLF2AmxMsFJWRLornITLuzEtgJ1_p?usp=sharing" target="_blank">Anti-money laundering &amp; Counter-fraud Compliance Statement</a><br />
        Pages: <a href="https://www.wtnsourcing.com">Home</a> | <a href="https://sourcing.wtnsourcing.com">Consumer Product Sourcing</a> | <a href="https://essentials.wtnsourcing.com">Daily Packaging</a> | <a href="https://premium.wtnsourcing.com">Custom &amp; Discreet Packaging</a> | <a href="https://kitting.wtnsourcing.com">Kitting &amp; Fulfillment</a> | <a href="https://compliance.wtnsourcing.com">Global Compliance</a> | <a href="https://process.wtnsourcing.com">Our SOP</a><br />
        Business Help: <a href="https://docs.google.com/presentation/d/1wx6HkvamvlbVaO1vFeV0tF2mCoYPTrOE4QhEWlm221U/edit?usp=sharing" target="_blank">Seamless Network Connectivity to the World in China: A Business Traveler's Guide</a> | <a href="https://docs.google.com/presentation/d/1V7jCa2ctO24ZThCgrOR8MsHUcm5DW2_9HLrWF-Qbs6o/edit?usp=sharing" target="_blank">Essential China Entry Guidelines for Overseas Business Travelers</a> | <a href="https://docs.google.com/presentation/d/1J0HLzcZ8ewi2_z0R6rV1ejk6kOk8l33kIq4_lrlfRWE/edit?usp=sharing" target="_blank">Seamless Payment Method in China</a> | <a href="https://docs.google.com/forms/d/e/1FAIpQLSfClIyOi4UrYZ-eoS8hsYqvvh4cL1WGDrPUvZyxW-wUekMo9A/viewform?usp=dialog" target="_blank">Satisfaction Survey</a>
      </p>
    </footer>
  </main>
</body>
</html>
EOF

cat << 'EOF' > src/pages/index.astro
---
import BaseLayout from '../layouts/BaseLayout.astro';
import { getPublishedPosts } from '../lib/notion.js';

const allPosts = await getPublishedPosts();

const sectionsConfig = [
  {
    key: 'Entry Guidelines',
    title: 'Essential China Entry Guidelines',
    subtitle: 'Practical compliance, connectivity, and payment guides for overseas business travelers visiting China.'
  },
  {
    key: 'Factory & Product',
    title: 'Factory Tour & Product Videos',
    subtitle: 'Unannounced factory audits, real-time production lines, and structural packaging tests direct from Guangdong.'
  },
  {
    key: 'Knowledge Hub',
    title: 'Knowledge Hub & Case Study',
    subtitle: 'In-depth engineering teardowns, AQL quality inspection walkthroughs, and cross-border DDP logistics.'
  }
];

const sections = sectionsConfig.map(sec => {
  const posts = allPosts
    .filter(p => p.section === sec.key)
    .sort((a, b) => {
      if (a.sectionPinned && !b.sectionPinned) return -1;
      if (!a.sectionPinned && b.sectionPinned) return 1;
      return new Date(b.date).getTime() - new Date(a.date).getTime();
    });
  return { ...sec, posts };
});
---
<BaseLayout>
  <!-- Hero Section -->
  <section class="gradient-full-section">
    <div class="gradient-inner">
      <h1 class="text-style-1">WTN Sourcing from China</h1>
      <h2 class="text-style-4">Unfiltered Sourcing from the Ground in China</h2>
      <p class="text-style-10">
        <em><strong>No theoretical advice, no sales fluff.</strong> Watch real factory audits, packaging stress tests, and live production QC direct from Guangdong's manufacturing floor.</em>
      </p>
      <a href="https://www.youtube.com/channel/UCS2t3X9hR_KH_fZ7NXxZTjQ" target="_blank" class="pill-button">
        <span>Subscribe on YouTube</span>
        <svg><use xlink:href="#icon-arrow-right"></use></svg>
      </a>
    </div>
  </section>

  <!-- 3 Categorized Video Streams -->
  {sections.map((sec, secIdx) => (
    <section>
      {secIdx > 0 && <hr class="divider-full" />}
      <hr class="divider-short" />
      <h2 class="text-style-8">{sec.title}</h2>
      <p class="text-style-3"><em>{sec.subtitle}</em></p>

      <div class="video-stream">
        {sec.posts.map((post, idx) => {
          const isReverse = idx % 2 === 1;
          return (
            <div class={`video-card-row ${isReverse ? 'reverse' : ''}`}>
              <div class="card-text-col">
                {post.sectionPinned && <span class="pinned-badge">★ Featured in {sec.key}</span>}
                <h3 class="text-style-6">{post.title}</h3>
                <p class="text-style-3"><em>{post.summary}</em></p>
                <a href={`/posts/${post.slug}`} class="pill-button">
                  <span>Article Reading</span>
                  <svg><use xlink:href="#icon-arrow-right"></use></svg>
                </a>
              </div>
              <div class="card-video-col">
                <div class="video-box">
                  {post.youtubeId ? (
                    <iframe
                      src={`https://www.youtube-nocookie.com/embed/${post.youtubeId}?rel=0&controls=1`}
                      title={post.title}
                      allowfullscreen
                      loading="lazy"
                    ></iframe>
                  ) : (
                    <div style="display:flex;align-items:center;justify-content:center;height:100%;color:#fff;">No Video URL</div>
                  )}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </section>
  ))}
</BaseLayout>
EOF

cat << 'EOF' > src/pages/posts/[slug].astro
---
import BaseLayout from '../../layouts/BaseLayout.astro';
import { getPublishedPosts, getPostBlocksHtml } from '../../lib/notion.js';

export async function getStaticPaths() {
  const posts = await getPublishedPosts();
  return posts.map(post => ({
    params: { slug: post.slug },
    props: { post },
  }));
}

const { post } = Astro.props;
const contentHtml = await getPostBlocksHtml(post.id);
const ogImage = post.youtubeId
  ? `https://img.youtube.com/vi/${post.youtubeId}/maxresdefault.jpg`
  : "https://blog.wtnsourcing.com/assets/images/share.jpg";
---
<BaseLayout title={`${post.title} | WTN Sourcing`} description={post.summary} ogImage={ogImage}>
  <article style="margin-top: 3.5rem;">
    <a href="/" style="color:#0DA5DB;text-decoration:none;font-family:'Instrument Sans',sans-serif;font-weight:500;">← Back to All Video Insights</a>
    
    <div style="margin-top: 1.5rem;">
      <span class="pinned-badge">{post.section}</span>
      <h1 class="text-style-8" style="margin-top:0.5rem;">{post.title}</h1>
      <p style="font-size:0.9rem;color:rgba(22,39,60,0.45);margin-bottom:2rem;">Published on {post.date}</p>
    </div>

    {post.youtubeId && (
      <div class="video-box" style="margin-bottom: 3rem;">
        <iframe
          src={`https://www.youtube-nocookie.com/embed/${post.youtubeId}?rel=0&controls=1`}
          title={post.title}
          allowfullscreen
        ></iframe>
      </div>
    )}

    {post.summary && (
      <p class="text-style-3" style="font-size:1.1rem;padding:1.5rem;background:#F4F8FB;border-left:4px solid #0DA5DB;border-radius:0.5rem;margin-bottom:2.5rem;">
        <em>{post.summary}</em>
      </p>
    )}

    <div class="notion-article-body" set:html={contentHtml} />

    <!-- Social Share Bar -->
    <div style="margin-top: 4rem; padding-top: 2rem; border-top: 1px solid rgba(22,39,60,0.1); display:flex; align-items:center; gap: 1rem; flex-wrap:wrap;">
      <strong style="color:#16273C;font-family:'Instrument Sans',sans-serif;">Share this insight:</strong>
      <a href={`https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(`https://blog.wtnsourcing.com/posts/${post.slug}`)}`} target="_blank" rel="noopener" class="pill-button" style="margin-top:0;height:2.5rem;font-size:0.9rem;">LinkedIn</a>
      <a href={`https://twitter.com/intent/tweet?url=${encodeURIComponent(`https://blog.wtnsourcing.com/posts/${post.slug}`)}&text=${encodeURIComponent(post.title)}`} target="_blank" rel="noopener" class="pill-button" style="margin-top:0;height:2.5rem;font-size:0.9rem;">Share on X</a>
    </div>
  </article>

  <style is:global>
    .notion-article-body h2 {
      font-family: 'Instrument Sans', sans-serif;
      color: #0DA5DB;
      font-size: 1.65em;
      margin: 2.5rem 0 1rem 0;
    }
    .notion-article-body h3 {
      font-family: 'Instrument Sans', sans-serif;
      color: #16273C;
      font-size: 1.3em;
      margin: 2rem 0 0.75rem 0;
    }
    .notion-article-body p {
      margin-bottom: 1.25rem;
      color: rgba(22, 39, 60, 0.75);
    }
    .notion-article-body ul, .notion-article-body ol {
      margin: 1rem 0 1.5rem 1.75rem;
      color: rgba(22, 39, 60, 0.75);
    }
    .notion-article-body li {
      margin-bottom: 0.5rem;
    }
    .notion-article-body blockquote, .notion-article-body .callout-box {
      padding: 1.25rem 1.5rem;
      background: #F4F8FB;
      border-left: 4px solid #33C4B4;
      border-radius: 0.5rem;
      margin: 1.5rem 0;
    }
    .notion-article-body .post-image {
      margin: 2.5rem 0;
      text-align: center;
    }
    .notion-article-body .post-image img {
      max-width: 100%;
      border-radius: 1.25rem;
      border: 5px solid #FFFFFF;
      box-shadow: 0rem 1.75rem 2.375rem 0rem rgba(22, 39, 60, 0.09);
    }
    .notion-article-body .post-video-frame {
      width: 100%;
      aspect-ratio: 16/9;
      border-radius: 1.25rem;
      border: 5px solid #FFFFFF;
      box-shadow: 0rem 1.75rem 2.375rem 0rem rgba(22, 39, 60, 0.09);
      overflow: hidden;
      margin: 2rem 0;
    }
    .notion-article-body .post-video-frame iframe, .notion-article-body .post-video-frame video {
      width: 100%;
      height: 100%;
      border: 0;
    }
  </style>
</BaseLayout>
EOF
echo "✅ 博客代码包已在桌面 wtn-video-blog 文件夹生成完毕！"