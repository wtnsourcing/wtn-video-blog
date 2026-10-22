import type { APIRoute } from 'astro';
// 引入项目中获取 Notion 文章列表的方法（请按实际文件路径调整）
import { getPosts } from '../lib/notion'; 

export const GET: APIRoute = async () => {
  const posts = await getPosts();
  const siteUrl = 'https://blog.wtnsourcing.com';

  // 静态固定页面（首页等）
  const staticPages = [
    { url: `${siteUrl}/`, changefreq: 'daily', priority: '1.0' },
  ];

  // 动态 Notion 文章页面
  const postPages = posts.map((post) => ({
    url: `${siteUrl}/posts/${post.slug}`, // 按实际博客文章路由规则配置
    lastmod: post.lastEditedTime ? new Date(post.lastEditedTime).toISOString().split('T')[0] : '',
    changefreq: 'weekly',
    priority: '0.8',
  }));

  const allPages = [...staticPages, ...postPages];

  // 拼接标准 XML 格式
  const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${allPages
  .map(
    (page) => `  <url>
    <loc>${page.url}</loc>
    ${page.lastmod ? `<lastmod>${page.lastmod}</lastmod>` : ''}
    <changefreq>${page.changefreq}</changefreq>
    <priority>${page.priority}</priority>
  </url>`
  )
  .join('\n')}
</urlset>`.trim();

  return new Response(sitemap, {
    headers: {
      'Content-Type': 'application/xml; charset=utf-8',
    },
  });
};
