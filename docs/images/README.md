# Images

`hero.png` (1600×640 base, rendered at 1.5×) sits at the top of the README. `social-preview.png`
(1280×640 base, rendered at 1.5×, must stay under GitHub's 1 MB limit) is uploaded by hand under
*Settings → Social preview*; there is no API for it. Both are rendered from the `.source.html`
files next to them, so a change is a text edit and a re-render, not a design tool session.

Render on macOS (any headless Chrome works the same):

```bash
cd docs/images
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1.5 --window-size=1600,640 --screenshot=hero.png "file://$PWD/hero.source.html"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1.5 --window-size=1280,640 --screenshot=social-preview.png "file://$PWD/social-preview.source.html"
```

The central tools page on simonvedder.com reuses `hero.png`; keep the file name.

Check the rendered hero before you commit it. The description sits to the left of the terminal
panel and does not wrap, so anything much over about sixty characters runs underneath it and is
cut off. Shorten the line in `hero.source.html` rather than the description in the manifest: the
image wants a phrase, the manifest wants a sentence.
