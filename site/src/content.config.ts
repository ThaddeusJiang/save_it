import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";

const post = z.object({
  title: z.string(),
  subtitle: z.string().optional(),
  date: z.coerce.date(),
  summary: z.string(),
  kind: z.enum(["release", "post"]).default("post"),
  version: z.string().optional(),
  previousVersion: z.string().optional(),
});

export const collections = {
  zh: defineCollection({
    loader: glob({ base: "../docs/blog/zh", pattern: "**/*.{md,mdx}" }),
    schema: post,
  }),
  en: defineCollection({
    loader: glob({ base: "../docs/blog/en", pattern: "**/*.{md,mdx}" }),
    schema: post,
  }),
};
