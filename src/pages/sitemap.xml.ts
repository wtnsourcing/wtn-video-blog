import { getPublishedPosts } from '../lib/notion.js';

export async function GET() {
  const posts = await getPublishedPosts();
  const siteUrl = 'https://blog.wtnsourcing.com';

  // 格式化日期为 W3C 标准 (YYYY-MM-DD)
  const formatDate = (dateStr) => {
    try {
      const d = new Date(dateStr);
      if (!isNaN(d.getTime())) {
        return d.toISOString().split('T')[0];
      }
    } catch (e) {}
    return new Date().toISOString().split('T')[0];
  };

  // 拼接标准的 Google XML Sitemap 结构
  const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <!-- 博客首页 -->
  <url>
    <loc>${siteUrl}/</loc>
    <lastmod>${new Date().toISOString().split('T')[0]}</lastmod>
    <changefreq>daily</changefreq>
    <priority>1.0</priority>
  </url>
  <!-- Notion 动态抓取的每篇文章详情页 -->
  ${posts
    .map(
      (post) => `
  <url>
    <loc>${siteUrl}/posts/${post.slug}</loc>
    <lastmod>${formatDate(post.date)}</lastmod>
    <changefreq>weekly</changefreq>
    <priority>0.8</priority>
  </url>`
    )
    .join('')}
</urlset>`.trim();

  return new Response(sitemap, {
    headers: {
      'Content-Type': 'application/xml; charset=utf-8',
    },
  });
}
