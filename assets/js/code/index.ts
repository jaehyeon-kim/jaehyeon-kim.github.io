// The theme's assets/js/code/index.ts at v1.13.3, changed so the code blocks get their
// panel (copy, line numbers, wrap, expand) whenever the script runs. The theme waits for
// DOMContentLoaded (theme commit f2f722c0, v1.6.2), but the main bundle is loaded async,
// so when it runs after that event the blocks are never set up. Here it runs at once when
// the document has already been parsed. Delete this file when the theme makes the same change.
import Component from "js/component";
import CodeBlock from "./code-block";

class Code implements Component {
  run() {
    const init = () => {
      document.querySelectorAll(".highlight").forEach((element: HTMLElement) => {
        const block = new CodeBlock(element);
        block.run();
      });
    };
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", init);
    } else {
      init();
    }
  }
}

export default Code;
