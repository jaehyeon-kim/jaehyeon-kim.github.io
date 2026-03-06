---
title: "Slides as Code: Integrating Reveal.js into my Hugo Blog"
date: 2026-03-09
draft: false
featured: true
comment: true
toc: true
reward: false
pinned: false
carousel: false
featuredImage: false
categories:
  - Web Development
tags:
  - Hugo
  - Reveal.js
  - JavaScript
  - Markdown
  - Marp
authors:
  - JaehyeonKim
images: []
description:
---

For a long time, I wanted a way to host my technical presentations directly on my website without relying on external platforms or bulky PDF exports. I wanted a **"Slides as Code"** approach: version-controlled Markdown files that live natively alongside my blog posts.

<!--more-->

## The Choice: Marp vs. Reveal.js

When looking for a solution, I initially considered **Marp**. 

Marp is undeniably easier to author initially; its VS Code extension with live preview makes designing slides feel like magic. However, it presented a hurdle for my Hugo integration as it requires separate compilation. 

Marp requires a separate build step to convert Markdown into standalone HTML. To integrate it, I would have to manually export each deck and move the resulting HTML into my `static/` folder. This felt "disconnected" from the Hugo ecosystem.

[**Reveal.js**](https://revealjs.com/), on the other hand, is a browser-based engine. By using Reveal.js, I can:
1.  **Stay Native:** Write pure Markdown in my `content/` folder just like a blog post.
2.  **Zero Manual Export:** Hugo handles the routing, and the browser handles the rendering at runtime.
3.  **Automatic Updates:** When I `git push` a Markdown file, the slides are live instantly. No separate compilation, no manual file moving.

## See it in Action

Before diving into the configuration, you can interact with the live demo below. This is the actual slide deck, rendered natively by Hugo and embedded directly into this post:

{{< slide "/slides/2026-03-09-reavealjs-demo/" >}}

*You can use your arrow keys to navigate the slides above, or click the "View Full Screen" button for the complete experience.*

## How the Configuration Works

I chose to keep slides independent from my main blog posts to avoid cluttering my main feed. Using Hugo's **Leaf Bundles**, each presentation gets its own folder for local assets like images.

```text
content/slides/
└── 2026-03-06-revealjs-demo/            
    ├── index.md                          # The slide content
    └── featured.jpg                      # Thumbnail for list view
```

### Custom "Shell" Layout

The secret is a custom layout at `layouts/slides/single.html`. Instead of using my theme's standard blog layout (which includes headers and sidebars), I created a clean "shell" that loads the Reveal.js engine from a CDN.

Crucially, I use `{{ .RawContent }}` instead of `{{ .Content }}`. This is because Reveal.js needs the raw Markdown syntax (like `---` for slide breaks) to calculate transitions in the browser, rather than the pre-rendered HTML Hugo usually provides.

### Advanced Technical Features

Because Reveal.js is a web-based runtime, it allows for high-end technical storytelling that traditional slide software can't easily handle:

#### Interactive Code Storytelling

Standard syntax highlighting is good, but Reveal.js allows for **directed walkthroughs**. Using a specific syntax like `[1|3-5|7]`, I can guide the audience through a specific block of code:

*   **Workflow:** First, I highlight the function definition, then step into the processing logic, and finally focus on the return statement. This "guided tour" of the code prevents the audience from getting overwhelmed by a large block of text.

#### Precision Media Styling

Using the `.element` comment syntax, I have granular control over CSS directly within the Markdown.

*   **Dynamic Backgrounds:** I can switch the entire slide context using the `data-background` attribute (like a high-impact "Cosmic" space background).
*   **CSS Overrides:** I can apply borders, rounded corners, and specific alignments, for example, centering a gold-bordered image without ever leaving the Markdown file.

#### Managing Cognitive Load with Fragments

To keep the audience focused on the current talking point, I use **Fragments**. This provides progressive disclosure of information. Beyond just "appearing," I can use classes like `grow` to emphasize a specific item or `highlight-red` to signal a warning, all triggered by a simple keypress.

#### Mathematical Precision (LaTeX/MathJax)

For engineering-heavy talks, raw text equations look unprofessional. By integrating **MathJax**, I can render complex mathematical models, such as Probability Density Functions, with the same precision found in a LaTeX paper. They remain sharp at any zoom level because they are rendered as vectors in the browser.

#### Diagrams as Code (Mermaid.js)

Instead of embedding static PNGs of architecture diagrams that inevitably become outdated, I use **Mermaid.js**. This allows me to define data pipelines, like a Kafka-to-Flink-to-Redis flow, directly in the Markdown text.

*   **Engineering Value:** Diagrams are now version-controlled and searchable. If the architecture changes, I update a few lines of text, and the visual layout re-renders automatically.

## Road Ahead: Professional Diagrams with Draw.io

While Mermaid.js is excellent for rapid, text-based flowcharts, complex system architectures often require the precision of a dedicated design tool. I am currently investigating the best way to integrate **Draw.io** into this "Slides-as-Code" workflow without losing the benefits of version control.

Currently, I am evaluating two brief paths:

*   **Editable SVGs:** Exporting diagrams as SVGs with embedded XML. This allows the slides to treat the diagram as a standard image while keeping the source file fully editable and version-controlled.
*   **The Draw.io JS Viewer:** Utilizing the official Diagrams.net JavaScript library to render `.drawio` XML files dynamically. This would enable interactive features like zooming and layer toggling directly during a presentation.

Moving forward, the goal is to ensure that even the most complex architectural designs remain as easy to maintain as a line of Markdown.

## Why this works for me

By leveraging Hugo's **Directory Inference**, any file I drop into `content/slides/` automatically inherits this powerful shell. I no longer "design" slides; I **engineer** them. 

While Marp might be slightly easier to "write," the Reveal.js integration is much easier to **maintain**. It turns my site into a single source of truth for both my articles and my presentations.

You can check out my latest presentations in the [Slides](/slides/) section!