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
