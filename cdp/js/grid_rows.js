/* Vaadin grid -> TSV rows.
   Cell text lives in LIGHT-DOM <vaadin-grid-cell-content> siblings (the <td>s in shadow DOM only
   hold <slot>s), so innerText of the page gives you a flat wall of values with no row boundaries.
   Header cells come first and define the column count; the rest chunk into rows in DOM order.
   Rows the grid has scrolled out of the buffer are simply absent -- page/scroll first, then dump. */
(() => {
  const g = document.querySelector('vaadin-grid');
  if (!g) return 'NOGRID';
  const cols = [...document.querySelectorAll('vaadin-grid-column')].length;
  const cc = [...document.querySelectorAll('vaadin-grid-cell-content')]
    .map(c => (c.textContent || '').replace(/\s+/g, ' ').trim());
  if (!cols) return cc.join('\n');
  const rows = [];
  for (let i = 0; i < cc.length; i += cols) rows.push(cc.slice(i, i + cols).join('\t'));
  return 'COLS=' + cols + ' ROWS=' + rows.length + '\n' + rows.join('\n');
})()
