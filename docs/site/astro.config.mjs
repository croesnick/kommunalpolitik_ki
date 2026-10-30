// Doku-Site „komki“ (Astro Starlight), veröffentlicht über GitHub Pages.
// Entscheidung und Abwägung: docs/research/2026-10-24-doku-site-und-bildband.md
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightLinksValidator from 'starlight-links-validator';

export default defineConfig({
  site: 'https://croesnick.github.io',
  base: '/kommunalpolitik_ki',
  integrations: [
    starlight({
      // Interne Links der .mdx-Seiten prüft der Validator beim Build
      // (Slug, Trailing-Slash, Anker, relative und lokale Links) — er läuft
      // damit automatisch im Pages-Build jedes PR. Externe Links prüft er
      // bewusst nicht; ein Netz-Check externer Links gehört laut
      // lychee.toml in einen eigenen Scheduled-Job statt ins PR-Gate.
      plugins: [starlightLinksValidator()],
      title: 'komki',
      description: 'Ein lokaler KI-Arbeitsraum für die Ratsarbeit: recherchieren mit Quellen, ohne dass Vertrauliches nach draußen gelangt.',
      defaultLocale: 'root',
      locales: { root: { label: 'Deutsch', lang: 'de' } },
      social: [
        { icon: 'github', label: 'Quellcode auf GitHub', href: 'https://github.com/croesnick/kommunalpolitik_ki' },
      ],
      editLink: { baseUrl: 'https://github.com/croesnick/kommunalpolitik_ki/edit/main/docs/site/' },
      lastUpdated: true,
      // Schriften selbst gehostet (Fontsource, SIL OFL): beim Aufruf gehen keine Daten an Google.
      customCss: [
        '@fontsource/atkinson-hyperlegible-next/400.css',
        '@fontsource/atkinson-hyperlegible-next/400-italic.css',
        '@fontsource/atkinson-hyperlegible-next/600.css',
        '@fontsource/atkinson-hyperlegible-next/700.css',
        '@fontsource/atkinson-hyperlegible-mono/400.css',
        '@fontsource/zilla-slab/600.css',
        './src/styles/komki.css',
      ],
      sidebar: [
        {
          label: 'komki',
          items: [
            { label: 'Worum es geht', slug: 'komki/worum-es-geht' },
            { label: 'So funktioniert komki', slug: 'komki/so-funktioniert-es' },
            { label: 'In Betrieb nehmen', slug: 'komki/in-betrieb-nehmen' },
            { label: 'Die Sicherheitsgrenze sehen', slug: 'komki/sicherheitsgrenze' },
            { label: 'Wenn etwas hakt', slug: 'komki/wenn-es-hakt' },
          ],
        },
        {
          label: 'Hintergrund',
          items: [
            { label: 'RFC: Vertrauliche KI-Arbeitsräume', link: 'https://github.com/croesnick/kommunalpolitik_ki/blob/main/docs/rfcs/0003-vertrauliche-ki-arbeitsraeume.md' },
            { label: 'Entscheidungshandbuch Tool-Zugang', link: 'https://github.com/croesnick/kommunalpolitik_ki/blob/main/docs/research/2026-10-20-tool-zugang-entscheidungshandbuch.md' },
            { label: 'Labbook der Tests', link: 'https://github.com/croesnick/kommunalpolitik_ki/blob/main/docs/research/2026-10-23-labbook-komki-connectoren.md' },
            { label: 'Connector-Vertrag', link: 'https://github.com/croesnick/kommunalpolitik_ki/blob/main/apps/komki_connector/CONTRACT.md' },
          ],
        },
      ],
    }),
  ],
});
