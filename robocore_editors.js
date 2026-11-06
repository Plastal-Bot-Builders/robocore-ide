// Blockly and Monaco for the RoboCore IDE, inside robocore_editors.html (#blocks or #code).
//
// The Flutter app (lib/ui/editor/web_editors_web.dart) shows that page in an iframe and calls
// window.rcEditor. Settings and the design come from docs/behaviour-spec.md (Handoff: Blockly,
// Handoff: Monaco) in the RoboCore IDE design.
//
// Blocks: Blockly 13 (web/vendor/blockly), Zelos look, the eight RoboCore categories, and an
// Arduino C++ generator that writes the same code as lib/engine/codegen.dart did for the old blocks.
// Code: Monaco 0.57 (web/vendor/monaco), C++ with Arduino and RoboCore suggestions and hovers,
// compile problems as markers.
'use strict';

(function () {
  const MODE = location.hash === '#code' ? 'code' : 'blocks';

  const INK = '#1B2A41', CREAM = '#F7F1E3', PAPER = '#FFFCF5', YELLOW = '#F2B01E';
  // The Navy theme's Pins & Serial blue: 3:1 against its workspace, with cream text at 4.5:1 (WCAG).
  const PINS_NAVY = '#4F6FA0';
  // Board context from the app: project name, board id and the pins the pin blocks offer.
  const CTX = { name: 'Sketch', board: 'v2', pins: ['13'], tonePins: ['47'], analogPins: [], userPin: 42, led: 2, theme: 'paper' };

  function loadScript(src) {
    return new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = src;
      s.onload = resolve;
      s.onerror = () => reject(new Error('Could not load ' + src));
      document.head.appendChild(s);
    });
  }

  function darker(hex, f) {
    const n = parseInt(hex.slice(1), 16);
    const c = [n >> 16, (n >> 8) & 255, n & 255].map((v) => Math.round(v * f));
    return '#' + c.map((v) => v.toString(16).padStart(2, '0')).join('');
  }

  // ======================================================================= Blocks (Blockly)
  //
  // The hardware-first block set (RoboCore_IDE_Design/docs/block-catalogue.md): 10 categories, and blocks
  // that say what the robot does. Blocks from the first version (Output, Input, Robotics, Communication …)
  // keep their types so saved projects open: those with the same meaning took the new words, the others
  // are still defined but no longer in the toolbox.

  const NOTES = { C4: 262, D4: 294, E4: 330, F4: 349, G4: 392, A4: 440, B4: 494, C5: 523, D5: 587, E5: 659, F5: 698, G5: 784, A5: 880, C6: 1047 };
  const COLOURS = {
    red: [255, 0, 0], green: [0, 255, 0], blue: [0, 0, 255], yellow: [255, 200, 0],
    purple: [160, 0, 255], white: [255, 255, 255], off: [0, 0, 0],
  };
  const DRIVE = { forward: [1, 1], backward: [-1, -1], left: [-1, 1], right: [1, -1] };
  const MELODIES = { 'power up': 'MELODY_POWER_UP', 'power down': 'MELODY_POWER_DOWN', success: 'MELODY_SUCCESS', error: 'MELODY_ERROR', alarm: 'MELODY_ALARM' };

  // Blocks that start a script: on start → setup(), forever and the "when …" hats → loop(),
  // "when I receive" → a function. "define" (My Blocks) also starts one.
  const HATS = ['rc_on_start', 'rc_forever', 'rc_when_user', 'rc_when_closer', 'rc_when_line', 'rc_when_tilt',
    'rc_when_timer', 'rc_when', 'rc_when_receive'];
  const isRoot = (type) => HATS.includes(type) || type === 'procedures_defnoreturn';

  // The categories, hardware first: [key, name, colour, Lucide icon].
  const ICONS = {
    zap: '<path d="M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z"/>',
    bot: '<path d="M12 8V4H8"/><rect width="16" height="12" x="4" y="8" rx="2"/><path d="M2 14h2"/><path d="M20 14h2"/><path d="M15 13v2"/><path d="M9 13v2"/>',
    gauge: '<path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/>',
    lightbulb: '<path d="M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5"/><path d="M9 18h6"/><path d="M10 22h4"/>',
    radio: '<path d="M4.9 19.1C1 15.2 1 8.8 4.9 4.9"/><path d="M7.8 16.2c-2.3-2.3-2.3-6.1 0-8.5"/><circle cx="12" cy="12" r="2"/><path d="M16.2 7.8c2.3 2.3 2.3 6.1 0 8.5"/><path d="M19.1 4.9C23 8.8 23 15.1 19.1 19"/>',
    repeat: '<path d="m17 2 4 4-4 4"/><path d="M3 11v-1a4 4 0 0 1 4-4h14"/><path d="m7 22-4-4 4-4"/><path d="M21 13v1a4 4 0 0 1-4 4H3"/>',
    sigma: '<path d="M18 7V5a1 1 0 0 0-1-1H6.5a.5.5 0 0 0-.4.8l4.5 6a2 2 0 0 1 0 2.4l-4.5 6a.5.5 0 0 0 .4.8H17a1 1 0 0 0 1-1v-2"/>',
    variable: '<path d="M8 21s-4-3-4-9 4-9 4-9"/><path d="M16 3s4 3 4 9-4 9-4 9"/><line x1="15" x2="9" y1="9" y2="15"/><line x1="9" x2="15" y1="9" y2="15"/>',
    blocks: '<rect width="7" height="7" x="14" y="3" rx="1"/><path d="M10 21V8a1 1 0 0 0-1-1H4a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-5a1 1 0 0 0-1-1H3"/>',
    plug: '<path d="M12 22v-5"/><path d="M9 8V2"/><path d="M15 8V2"/><path d="M18 8v5a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4V8Z"/>',
  };
  const CATS = [
    ['events', 'Events', YELLOW, 'zap'],
    ['movement', 'Movement', '#2F6BBF', 'bot'],
    ['motors', 'Motors', '#B84A26', 'gauge'],
    ['light', 'Light & Sound', '#7A4FB5', 'lightbulb'],
    ['sensors', 'Sensors', '#0F7680', 'radio'],
    ['control', 'Control', '#8A5A00', 'repeat'],
    ['operators', 'Operators', '#2F7A4C', 'sigma'],
    ['variables', 'Variables', '#B23E7A', 'variable'],
    ['myblocks', 'My Blocks', '#5B6577', 'blocks'],
    ['pins', 'Pins & Serial', INK, 'plug'],
  ];
  // Lucide icons are drawn on a 24 px grid; at 14-18 px they need a heavier line to read like the design's.
  const svgUri = (paths, stroke, size = 24, weight = 2) => 'data:image/svg+xml;utf8,' + encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="${stroke}" ` +
    `stroke-width="${weight}" stroke-linecap="round" stroke-linejoin="round">${paths}</svg>`);
  // The robot and gauge marks at the start of Movement and Motors blocks.
  const iconField = (name) => ({ type: 'field_image', src: svgUri(ICONS[name], CREAM, 24, 2.4), width: 18, height: 18, alt: '' });
  const CHEVRON = '<path d="m6 9 6 6 6-6"/>';
  const FIT = '<path d="M8 3H5a2 2 0 0 0-2 2v3"/><path d="M21 8V5a2 2 0 0 0-2-2h-3"/><path d="M3 16v3a2 2 0 0 0 2 2h3"/><path d="M16 21h3a2 2 0 0 0 2-2v-3"/>';
  const ZOOM_IN = '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/><path d="M11 8v6"/><path d="M8 11h6"/>';
  const ZOOM_OUT = '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/><path d="M8 11h6"/>';

  function theme(navy) {
    const styles = {};
    for (const [k, , c] of CATS) {
      const primary = navy && k === 'pins' ? PINS_NAVY : c;
      styles['rc_' + k] = { colourPrimary: primary, colourSecondary: darker(primary, 0.85), colourTertiary: INK };
    }
    // Blockly's own blocks take the RoboCore colours (and categories, see defineBlocks()).
    Object.assign(styles, {
      logic_blocks: styles.rc_control, loop_blocks: styles.rc_control, math_blocks: styles.rc_operators,
      text_blocks: styles.rc_operators, variable_blocks: styles.rc_variables, variable_dynamic_blocks: styles.rc_variables,
      procedure_blocks: styles.rc_myblocks,
    });
    const cats = {};
    for (const [k] of CATS) cats[k] = { colour: styles['rc_' + k].colourPrimary };
    return Blockly.Theme.defineTheme(navy ? 'robocore-navy' : 'robocore-paper', {
      base: Blockly.Themes.Classic,
      blockStyles: styles,
      categoryStyles: cats,
      componentStyles: {
        workspaceBackgroundColour: navy ? '#17253A' : PAPER,
        toolboxBackgroundColour: navy ? INK : PAPER,
        toolboxForegroundColour: navy ? CREAM : INK,
        flyoutBackgroundColour: navy ? '#22344F' : CREAM,
        flyoutForegroundColour: navy ? CREAM : INK,
        flyoutOpacity: 1,
        scrollbarColour: navy ? CREAM : INK,
        scrollbarOpacity: 0.4,
        insertionMarkerColour: navy ? CREAM : INK,
        insertionMarkerOpacity: 0.3,
        // Navy on paper (yellow there is 1.9:1, under WCAG's 3:1), the box yellow on navy.
        selectedGlowColour: navy ? YELLOW : INK,
        cursorColour: navy ? YELLOW : INK,
        markerColour: navy ? YELLOW : INK,
      },
      // Blockly's size is in points: 9.75 pt = 13 px, the design's Block/Label.
      fontStyle: { family: 'Barlow, sans-serif', weight: '600', size: 9.75 },
      startHats: true,
    });
  }

  // Zelos, plus a class on yellow (Events) blocks so their labels can be navy instead of cream, and the design's
  // block metrics (RoboCore_IDE_Design 05_blocks.js): 40 px statements, 24 px fields, a chevron on dropdowns.
  // Zelos sizes everything from its grid unit: 4 px makes 48 px statements, 10/3 px makes 40.
  function registerRenderer() {
    class RcConstants extends Blockly.zelos.ConstantProvider {
      constructor() {
        super(10 / 3);
        this.FIELD_BORDER_RECT_HEIGHT = 24;
        this.FIELD_DROPDOWN_BORDER_RECT_HEIGHT = 24;
        this.FIELD_BORDER_RECT_X_PADDING = 8;
        this.FIELD_DROPDOWN_SVG_ARROW_PADDING = 6;
        this.FIELD_DROPDOWN_SVG_ARROW_DATAURI = svgUri(CHEVRON, CREAM, 12, 2.5);
        this.FIELD_DROPDOWN_COLOURED_DIV = false; // the design's white menu, not one in the block's colour
        this.MEDIUM_PADDING = 9; // between the parts of a block and at its ends (the design: 8-12)
        this.STATEMENT_INPUT_PADDING_LEFT = 20; // the arm of a C-block
      }
    }
    class RcPathObject extends Blockly.zelos.PathObject {
      applyColour(block) {
        super.applyColour(block);
        const primary = (block.style && block.style.colourPrimary || '').toUpperCase();
        this.svgRoot.classList.toggle('rcNavyText', primary === YELLOW);
        this.svgRoot.classList.toggle('rcInkBlock', primary === INK);
      }
    }
    class RcRenderer extends Blockly.zelos.Renderer {
      makeConstants_() {
        return new RcConstants();
      }
      makePathObject(root, style) {
        return new RcPathObject(root, style, this.getConstants());
      }
    }
    Blockly.blockRendering.register('robocore', RcRenderer);
    const css = document.createElement('style');
    // The toolbox grows with the desktop apps' display size (--rc-zoom, set by setZoom).
    const z = (px) => `calc(${px}px * var(--rc-zoom, 1))`;
    css.textContent = [
      '.robocore-renderer .blocklyText { fill: ' + CREAM + '; }',
      '.robocore-renderer .rcNavyText > .blocklyText, .robocore-renderer .rcNavyText > g > .blocklyText { fill: ' + INK + '; }',
      '.robocore-renderer .blocklyEditableText > .blocklyText:not(.blocklyDropdownText) { fill: ' + INK + '; }',
      // Number and text fields are white pills, as in the design (dropdowns keep 4 px corners).
      '.robocore-renderer .blocklyInputField > .blocklyFieldRect { rx: 12px; ry: 12px; }',
      // Empty yes/no slots are a darker tint of the block (navy over it), not solid navy.
      '.robocore-renderer .blocklyOutlinePath { fill: rgba(27,42,65,.28) !important; }',
      '.robocore-renderer .rcNavyText > .blocklyOutlinePath { fill: rgba(27,42,65,.14) !important; }',
      // A dropdown's menu: white, the chosen option on a yellow row with a check on the right (the design's Menu Item).
      // No edge (the design has had no outlines since v1.0.1): the shadow sets the menu apart.
      '.blocklyDropDownDiv { background: #FFFFFF !important; border: none !important; border-radius: 8px !important;' +
        ' box-shadow: 0 8px 24px rgba(27,42,65,.16) !important; }',
      '.blocklyDropDownDiv .blocklyDropDownArrow { background: #FFFFFF !important; border-color: transparent !important; }',
      '.blocklyDropDownDiv .blocklyMenu { padding: 4px !important; }',
      '.blocklyDropDownDiv .blocklyMenuItem { position: relative; border-radius: 6px; padding: 7px 36px 7px 10px !important; min-width: 120px;' +
        ' font: 500 13px Barlow, sans-serif; }',
      '.blocklyDropDownDiv .blocklyMenuItemContent { color: ' + INK + ' !important; }',
      '.blocklyDropDownDiv .blocklyMenuItemHighlight { background: #F0EDE7 !important; }',
      '.blocklyDropDownDiv .blocklyMenuItemSelected { background: #FCE9BF !important; font-weight: 600; }',
      '.blocklyDropDownDiv .blocklyMenuItemSelected .blocklyMenuItemCheckbox { position: absolute; right: 10px; top: 50%; margin: -8px 0 0 0;' +
        ` float: none; background: url("${svgUri('<path d="M20 6 9 17l-5-5"/>', INK, 16, 2.5)}") center / 16px no-repeat !important; }`,
      '.rcNavy .blocklyDropDownDiv, .rcNavy .blocklyDropDownDiv .blocklyDropDownArrow { background: ' + INK + ' !important; border-color: transparent !important; }',
      '.rcNavy .blocklyDropDownDiv .blocklyMenuItemContent { color: ' + CREAM + ' !important; }',
      '.rcNavy .blocklyDropDownDiv .blocklyMenuItemHighlight { background: #22344F !important; }',
      '.rcNavy .blocklyDropDownDiv .blocklyMenuItemSelected { background: rgba(242,176,30,.2) !important; }',
      `.rcNavy .blocklyDropDownDiv .blocklyMenuItemSelected .blocklyMenuItemCheckbox { background-image: url("${svgUri('<path d="M20 6 9 17l-5-5"/>', CREAM, 16, 2.5)}") !important; }`,
      // Dropdowns are a darker tint of the block (navy over it), without an outline.
      '.robocore-renderer .blocklyDropdownField > .blocklyFieldRect { fill: rgba(27,42,65,.28) !important; stroke: none !important; }',
      '.robocore-renderer .rcNavyText > .blocklyDropdownField > .blocklyFieldRect { fill: rgba(27,42,65,.14) !important; }',
      // The gear on "if" (else if / else) in the block palette's navy and cream, not Blockly's blue.
      '.robocore-renderer .blocklyMutatorIcon .blocklyIconShape { fill: ' + INK + '; stroke: none; }',
      '.robocore-renderer .blocklyMutatorIcon .blocklyIconSymbol { fill: ' + CREAM + '; }',
      // On the yellow Events blocks the dropdown chevron is navy, like their labels.
      '.robocore-renderer .rcNavyText > .blocklyDropdownField > image { filter: brightness(0.15); }',
      // The toolbox (the design's Block Category rows): 160 px wide, 34 px rows, 22 px colour chips.
      // No divider line between the toolbox and the workspace.
      '.blocklyToolbox { width: ' + z(160) + '; box-sizing: border-box; padding: ' + z(12) + ' ' + z(8) + ' !important; border: none !important; }',
      '.blocklyToolboxCategoryContainer { margin: 0 0 ' + z(2) + '; }',
      '.blocklyToolboxCategory { position: relative; height: ' + z(34) + '; line-height: ' + z(34) + '; margin: 0;' +
        ' padding: 0 ' + z(8) + ' 0 ' + z(10) + ' !important;' +
        ' border-radius: 6px; border-left: none !important; cursor: pointer; }',
      '.blocklyTreeRowContentContainer { display: flex; align-items: center; gap: ' + z(8) + '; height: ' + z(34) + '; }',
      '.blocklyToolboxCategoryLabel { font: 500 ' + z(13) + '/' + z(16) + ' Barlow, sans-serif; color: #5B6573; white-space: nowrap; }',
      '.blocklyToolboxCategory:not(.blocklyToolboxSelected):hover { background: rgba(27,42,65,.05); }',
      '.blocklyToolboxSelected { background: #FCE9BF !important; }',
      '.blocklyToolboxSelected .blocklyToolboxCategoryLabel { color: ' + INK + ' !important; font-weight: 600; }',
      '.blocklyToolboxSelected::before { content: ""; position: absolute; left: 0; top: ' + z(8) + '; width: 3px; height: ' + z(18) + ';' +
        ' border-radius: 0 2px 2px 0; background: ' + YELLOW + '; }',
      '.robocore-navy-theme .blocklyToolboxCategoryLabel { color: rgba(247,241,227,.78); }',
      '.robocore-navy-theme .blocklyToolboxCategory:not(.blocklyToolboxSelected):hover { background: rgba(247,241,227,.06); }',
      '.robocore-navy-theme .blocklyToolboxSelected { background: rgba(242,176,30,.20) !important; }',
      '.robocore-navy-theme .blocklyToolboxSelected .blocklyToolboxCategoryLabel { color: ' + CREAM + ' !important; }',
      '.blocklyWidgetDiv .blocklyMenu, .blocklyDropDownDiv { font-family: Barlow, sans-serif; }',
      // The flyout: a title (category swatch + name) over the blocks, and the design's buttons.
      '.injectionDiv .blocklyFlyout .rcFlyoutTitle > .blocklyFlyoutLabelText { font: 600 18px "Barlow Condensed", Barlow, sans-serif;' +
        ' letter-spacing: .54px; fill: ' + INK + ' !important; }',
      '.robocore-navy-theme .blocklyFlyout .rcFlyoutTitle > .blocklyFlyoutLabelText { fill: ' + CREAM + ' !important; }',
      // The design's Secondary button: a soft brandSoft fill, no outline.
      '.blocklyFlyoutButton .blocklyFlyoutButtonBackground { fill: #FCE9BF; stroke: none; }',
      '.blocklyFlyoutButton:hover .blocklyFlyoutButtonBackground { fill: #F9DB96; }',
      '.robocore-navy-theme .blocklyFlyoutButton .blocklyFlyoutButtonBackground { fill: #3B3220; }',
      '.robocore-navy-theme .blocklyFlyoutButton:hover .blocklyFlyoutButtonBackground { fill: #50421F; }',
      '.robocore-navy-theme .blocklyFlyoutButton .blocklyText { fill: ' + CREAM + ' !important; }',
      '.blocklyFlyoutButton .blocklyText { fill: ' + INK + ' !important; font: 600 13px Barlow, sans-serif; }',
      '.blocklyFlyoutButtonShadow { display: none; }',
      // Zoom buttons and trashcan drawn as in the design (Blockly's sprite images hidden).
      '.blocklyZoom > image, .blocklyZoom > svg > image, .blocklyTrash > image, .blocklyTrashLid > svg { display: none; }',
      '.blocklyZoom { cursor: pointer; }',
      '.rcZoomBox { fill: #FFFFFF; stroke: none; }',
      '.blocklyZoom:hover .rcZoomBox { fill: ' + CREAM + '; }',
      '.rcIcon { fill: none; stroke: ' + INK + '; stroke-width: 2.25px; stroke-linecap: round; stroke-linejoin: round; }',
      '.robocore-navy-theme .rcZoomBox { fill: #22344F; }',
      '.robocore-navy-theme .blocklyZoom:hover .rcZoomBox { fill: #2C405E; }',
      '.robocore-navy-theme .rcIcon { stroke: ' + CREAM + '; }',
      '.blocklyTrashLid { opacity: 1 !important; }',
      '.rcTrashPart { fill: ' + PAPER + '; stroke: ' + INK + '; stroke-width: 1.5px; }',
      '.rcTrashRib { stroke: ' + INK + '; stroke-width: 1.5px; stroke-linecap: round; }',
      '.blocklyTrashOpen .rcTrashPart { fill: #FCE9BF; }',
      '.robocore-navy-theme .rcTrashPart { fill: #22344F; stroke: ' + CREAM + '; }',
      '.robocore-navy-theme .rcTrashRib { stroke: ' + CREAM + '; }',
      '.rcTrashCount { display: none; }',
      '.blocklyTrashFull .rcTrashCount { display: inline; }',
      '.rcTrashCount > rect { fill: ' + INK + '; }',
      '.rcTrashCount > text { fill: ' + CREAM + '; font: 600 11px Barlow, sans-serif; }',
      // Selection and keyboard focus (BK-16): navy on paper and the box yellow on navy, where they reach 3:1 (WCAG). The
      // yellow Events blocks keep navy (cream on navy), and the navy Pins & Serial blocks on paper take the yellow.
      '.robocore-renderer.injectionDiv { --blockly-active-node-color: ' + INK + '; --blockly-active-tree-color: ' + INK + '; }',
      '.robocore-renderer.robocore-navy-theme.injectionDiv, .robocore-renderer.injectionDiv .robocore-navy-theme {' +
        ' --blockly-active-node-color: ' + YELLOW + '; --blockly-active-tree-color: ' + YELLOW + '; }',
      '.robocore-renderer .rcNavyText.blocklySelected > .blocklyPath.blocklyPathSelected { filter: none; stroke: ' + INK + '; stroke-width: 2.5px; }',
      '.blocklyKeyboardNavigation .robocore-renderer .rcNavyText > .blocklyPath.blocklyActiveFocus,' +
        ' .blocklyKeyboardNavigation.robocore-renderer .rcNavyText > .blocklyPath.blocklyActiveFocus { stroke: ' + INK + '; }',
      '.robocore-navy-theme .rcNavyText.blocklySelected > .blocklyPath.blocklyPathSelected { stroke: ' + CREAM + '; }',
      '.blocklyKeyboardNavigation .robocore-navy-theme .rcNavyText > .blocklyPath.blocklyActiveFocus,' +
        ' .blocklyKeyboardNavigation.robocore-navy-theme .rcNavyText > .blocklyPath.blocklyActiveFocus { stroke: ' + CREAM + '; }',
      '.robocore-renderer .rcInkBlock.blocklySelected > .blocklyPath.blocklyPathSelected { filter: none; stroke: ' + YELLOW + '; stroke-width: 2.5px; }',
      '.blocklyKeyboardNavigation .robocore-renderer .rcInkBlock > .blocklyPath.blocklyActiveFocus,' +
        ' .blocklyKeyboardNavigation.robocore-renderer .rcInkBlock > .blocklyPath.blocklyActiveFocus { stroke: ' + YELLOW + '; }',
      '.robocore-renderer .blocklyHighlightedConnectionPath { filter: drop-shadow(0 0 1px ' + INK + '); }',
      // A round chip in the category's colour with its icon (the design's toolbox).
      '.rcCatIcon { display: inline-block; flex: none; width: ' + z(22) + '; height: ' + z(22) + '; border-radius: 50%;' +
        ' background-repeat: no-repeat; background-position: center; background-size: ' + z(14) + ' ' + z(14) + '; }',
      ...CATS.map(([k, , c, icon]) => `.rcCat_${k} { background-color: ${c}; background-image: url("${svgUri(ICONS[icon], k === 'events' ? INK : CREAM, 24, 2.6)}"); }`),
      // On the navy toolbox the navy Pins & Serial chip takes the dark theme's lighter blue.
      '.robocore-navy-theme .rcCat_pins { background-color: ' + PINS_NAVY + '; }',
    ].join('\n');
    document.head.appendChild(css);
  }

  // The flyout as in the design: 16 px padding and gaps, and a title with the category's colour swatch.
  function registerFlyout() {
    class RcFlyout extends Blockly.VerticalFlyout {
      constructor(options) {
        super(options);
        this.MARGIN = 16;
        this.GAP_Y = 16;
      }
      show(contents) {
        super.show(contents);
        decorateFlyout(this.getWorkspace().getCanvas());
      }
      // The palette keeps its size when the workspace zooms (as in Scratch and the design); Blockly's default
      // follows the workspace. A block taken out of it takes the workspace's size.
      getFlyoutScale() {
        return 1;
      }
      // At least the design's 288 px; Blockly fits the flyout to its widest block.
      reflowInternal_() {
        super.reflowInternal_();
        if (this.width_ < 288) {
          this.width_ = 288;
          this.position();
          this.targetWorkspace.resizeContents();
          this.targetWorkspace.recordDragTargets();
        }
      }
    }
    Blockly.registry.register(Blockly.registry.Type.FLYOUTS_VERTICAL_TOOLBOX, 'rcFlyout', RcFlyout);
    // "Make a variable…" and "Make a block…": 32 px buttons with 14 px sides (the design's flyout button).
    Blockly.FlyoutButton.TEXT_MARGIN_X = 14;
    Blockly.FlyoutButton.TEXT_MARGIN_Y = 8;
    Blockly.FlyoutButton.BORDER_RADIUS = 6;
  }

  const SVG_NS = 'http://www.w3.org/2000/svg';
  function svgEl(tag, attrs, parent, html) {
    const e = document.createElementNS(SVG_NS, tag);
    for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, String(v));
    if (html) e.innerHTML = html;
    if (parent) parent.appendChild(e);
    return e;
  }

  // Blockly centres a label's text; the title starts at the left, after a 14 px swatch.
  function decorateFlyout(canvas) {
    for (const g of canvas.querySelectorAll('.rcFlyoutTitle')) {
      if (g.querySelector('.rcSwatch')) continue;
      const text = g.querySelector('.blocklyFlyoutLabelText');
      const key = [...g.classList].find((c) => c.startsWith('rcTitle_')).slice(8);
      const navy = CTX.theme === 'navy' && key === 'pins';
      text.setAttribute('text-anchor', 'start');
      text.setAttribute('x', '24');
      const b = text.getBBox();
      svgEl('rect', { class: 'rcSwatch', x: 0, y: b.y + b.height / 2 - 7, width: 14, height: 14, rx: 4,
        fill: navy ? PINS_NAVY : CATS.find((x) => x[0] === key)[2] }, g);
    }
  }

  // Zoom buttons (fit, zoom in, zoom out) and the trashcan, drawn as in the design inside Blockly's own groups,
  // so Blockly still places them, handles their clicks and opens the trashcan's lid.
  function drawControls(w) {
    const root = w.getParentSvg();
    for (const [cls, icon] of [['blocklyZoomReset', FIT], ['blocklyZoomIn', ZOOM_IN], ['blocklyZoomOut', ZOOM_OUT]]) {
      const g = root.querySelector('.' + cls);
      if (!g || g.querySelector('.rcZoomBox')) continue;
      svgEl('rect', { class: 'rcZoomBox', x: 0.5, y: 0.5, width: 31, height: 31, rx: 8 }, g);
      svgEl('g', { class: 'rcIcon', transform: 'translate(7 7) scale(.75)' }, g, icon);
    }
    const t = root.querySelector('.blocklyTrash');
    if (!t || t.querySelector('.rcTrashPart')) return;
    // In the trashcan's 47 x 60 box; the lid group turns about its right end (Blockly's CSS).
    const body = svgEl('g', {}, null);
    svgEl('path', { class: 'rcTrashPart', d: 'M10.5 22H36.5Q38.5 22 38.5 24V50Q38.5 56 32.5 56H14.5Q8.5 56 8.5 50V24Q8.5 22 10.5 22Z' }, body);
    for (const x of [16.5, 23.5, 30.5]) svgEl('line', { class: 'rcTrashRib', x1: x, y1: 28, x2: x, y2: 50 }, body);
    const count = svgEl('g', { class: 'rcTrashCount' }, body);
    svgEl('rect', { x: 28, y: 36, width: 18, height: 16, rx: 8 }, count);
    svgEl('text', { x: 37, y: 48, 'text-anchor': 'middle' }, count);
    t.insertBefore(body, t.querySelector('.blocklyTrashLid'));
    const lid = t.querySelector('.blocklyTrashLid');
    svgEl('rect', { class: 'rcTrashPart', x: 17.5, y: 12, width: 12, height: 5, rx: 2 }, lid);
    svgEl('rect', { class: 'rcTrashPart', x: 5.5, y: 16, width: 36, height: 5, rx: 2 }, lid);
    const update = () => {
      const n = w.trashcan && w.trashcan.contents ? w.trashcan.contents.length : 0;
      count.querySelector('text').textContent = n > 9 ? '9+' : String(n);
    };
    w.addChangeListener((e) => { if (e.type === Blockly.Events.BLOCK_DELETE || e.type === Blockly.Events.TRASHCAN_OPEN) setTimeout(update, 0); });
    update();
  }

  function dropdown(values) {
    return values.map((v) => (Array.isArray(v) ? v : [v, v]));
  }

  // Pins depend on the board, so these menus are built when they open; on the RoboCore V2 they read IO37 …,
  // on an Uno pins 14 to 19 read A0 to A5. The current value always stays in the list so saved projects load
  // whatever the board. [list]: pins, tonePins or analogPins (CTX, from the app).
  const SAVED_PINS = new Set();
  const isUnoAnalog = (n) => CTX.board === 'uno' && n >= 14 && n <= 19;
  // An HC-SR04's TRIG and ECHO pins when the sketch doesn't say: the usual 9 and 10 on an Uno, 5 and 18 on an ESP32.
  const sonarDefaults = () => (CTX.board === 'uno' ? ['9', '10'] : ['5', '18']);
  const pinLabel = (p) => (CTX.board === 'v2' ? 'IO' + p : isUnoAnalog(+p) ? 'A' + (p - 14) : p);
  function pinMenu(list) {
    return function () {
      const pins = CTX[list] && CTX[list].length ? CTX[list] : CTX.pins;
      const opts = pins.map((p) => [pinLabel(p), p]);
      const v = this && typeof this.getValue === 'function' ? this.getValue() : null;
      for (const x of [v, ...SAVED_PINS]) if (x && !opts.some((o) => o[1] === x)) opts.push([x, x]);
      return opts;
    };
  }

  // Messages for "when I receive" / "broadcast": every name used in the workspace, plus New message….
  const MESSAGES = new Set(['message1']);
  function messageMenu() {
    const ws = this && this.getSourceBlock && this.getSourceBlock() && this.getSourceBlock().workspace;
    if (ws) for (const b of ws.getAllBlocks(false)) if (b.getField('MSG')) MESSAGES.add(b.getFieldValue('MSG'));
    return [...MESSAGES].sort().map((m) => [m, m]).concat([['New message…', '__new__']]);
  }
  function messageValidator(v) {
    if (v !== '__new__') return v;
    const field = this;
    Blockly.dialog.prompt('Name of the new message:', '', (name) => {
      const n = (name || '').trim();
      if (!n) return;
      MESSAGES.add(n);
      field.setValue(n);
    });
    return null;
  }
  // Messages and pins in a saved workspace, so its dropdowns accept them while it loads.
  function rememberMessages(json) {
    const walk = (o) => {
      if (!o || typeof o !== 'object') return;
      if (o.fields && typeof o.fields.MSG === 'string') MESSAGES.add(o.fields.MSG);
      if (o.fields && typeof o.fields.PIN === 'string') SAVED_PINS.add(o.fields.PIN);
      for (const v of Object.values(o)) walk(v);
    };
    walk(json);
  }

  function defineBlocks() {
    const num = (name, check = 'Number') => ({ type: 'input_value', name, check });
    const stmt = (o) => Object.assign({ previousStatement: null, nextStatement: null }, o);
    const hat = (o) => Object.assign({ message1: '%1', args1: [{ type: 'input_statement', name: 'DO' }] }, o);
    const dd = (name, values) => ({ type: 'field_dropdown', name, options: dropdown(values) });
    // Text values are white pills like numbers (the design), so Blockly's text block loses its quote marks.
    Blockly.Blocks['text'] = {
      init() {
        this.jsonInit({ type: 'text', message0: '%1', args0: [{ type: 'field_input', name: 'TEXT', text: '' }], output: 'String',
          style: 'text_blocks', tooltip: Blockly.Msg.TEXT_TEXT_TOOLTIP, helpUrl: Blockly.Msg.TEXT_TEXT_HELPURL });
      },
    };
    // "join" as in the design (and Scratch): two values on one row, no gear; join a join for more pieces.
    // Projects saved with Blockly's own join (any number of pieces) still open: their itemCount adds the rest.
    Blockly.Blocks['text_join'] = {
      init() {
        this.itemCount_ = 2;
        this.setStyle('rc_operators');
        this.setOutput(true, 'String');
        this.setInputsInline(true);
        this.setTooltip('Joins two values into one text: String(a) + b');
        this.updateShape_();
      },
      saveExtraState() {
        return this.itemCount_ === 2 ? null : { itemCount: this.itemCount_ };
      },
      loadExtraState(state) {
        this.itemCount_ = Math.max(2, (state && state.itemCount) || 2);
        this.updateShape_();
      },
      updateShape_() {
        for (let i = 0; i < this.itemCount_; i++) {
          if (!this.getInput('ADD' + i)) {
            const input = this.appendValueInput('ADD' + i);
            if (i === 0) input.appendField('join');
          }
        }
        for (let i = this.itemCount_; this.getInput('ADD' + i); i++) this.removeInput('ADD' + i);
      },
    };
    Blockly.common.defineBlocksWithJsonArray([
      // ---- Events
      hat({ type: 'rc_on_start', message0: 'on start', style: 'rc_events', tooltip: 'Runs once when the robot starts: void setup() { … }' }),
      hat({ type: 'rc_forever', message0: 'forever', style: 'rc_events', tooltip: 'Runs again and again: void loop() { … }' }),
      hat({ type: 'rc_when_user', message0: 'when USER button is pressed', style: 'rc_events',
        tooltip: 'Runs each time USER is pressed. Checked on every pass of forever, so keep forever free of long waits.' }),
      hat({ type: 'rc_when_closer', message0: 'when obstacle is closer than %1 cm', args0: [num('CM')], style: 'rc_events',
        tooltip: 'Runs each time something comes closer than this.' }),
      hat({ type: 'rc_when_line', message0: 'when the line is %1', args0: [dd('STATE', ['found', 'lost'])], style: 'rc_events',
        tooltip: 'Runs each time the line sensor finds (or loses) the line.' }),
      hat({ type: 'rc_when_tilt', message0: 'when the robot is %1', args0: [dd('STATE', ['tilted', 'shaken', 'flat'])], style: 'rc_events',
        tooltip: 'Runs each time the robot is tilted, shaken or put flat.' }),
      hat({ type: 'rc_when_timer', message0: 'when timer > %1 s', args0: [num('SECS')], style: 'rc_events',
        tooltip: 'Runs once when the timer passes this many seconds (again after reset timer).' }),
      hat({ type: 'rc_when', message0: 'when %1', args0: [num('COND', 'Boolean')], style: 'rc_events',
        tooltip: 'Runs each time the yes / no block becomes yes.' }),
      // ---- Movement (both wheels together)
      stmt({ type: 'rc_move', message0: '%1 move %2 for %3 %4', style: 'rc_movement', inputsInline: true,
        args0: [iconField('bot'), dd('DIR', ['forward', 'backward']), num('AMOUNT'), dd('UNIT', ['cm', 'rotations', 'seconds'])],
        tooltip: 'Drives straight and waits until done: robot.move(10, CM);' }),
      stmt({ type: 'rc_turn', message0: '%1 turn %2 for %3 °', style: 'rc_movement', inputsInline: true,
        args0: [iconField('bot'), dd('DIR', ['right', 'left']), num('DEG')], tooltip: 'Turns on the spot (IMU) and waits: robot.turn(90);' }),
      stmt({ type: 'rc_start_moving', message0: '%1 start moving %2', style: 'rc_movement',
        args0: [iconField('bot'), dd('DIR', ['forward', 'backward'])], tooltip: 'Keeps driving until stop moving: robot.start(FORWARD);' }),
      stmt({ type: 'rc_steer', message0: '%1 start moving, steering %2', style: 'rc_movement', inputsInline: true,
        args0: [iconField('bot'), num('STEER')], tooltip: '-100 to 100: 0 straight, 50 one wheel stopped, 100 spins right: robot.steer(30);' }),
      stmt({ type: 'rc_drive_lr', message0: '%1 drive left %2 % right %3 %', style: 'rc_movement', inputsInline: true,
        args0: [iconField('bot'), num('L'), num('R')], tooltip: 'Each wheel\'s speed, -100 to 100: motors.drive(50, 50);' }),
      stmt({ type: 'rc_stop_moving', message0: '%1 stop moving', style: 'rc_movement', args0: [iconField('bot')], tooltip: 'Brakes: robot.stop();' }),
      stmt({ type: 'rc_move_speed', message0: '%1 set movement speed to %2 %', style: 'rc_movement', inputsInline: true,
        args0: [iconField('bot'), num('PCT')], tooltip: 'For move, turn, start moving and steering: robot.setSpeed(50);' }),
      stmt({ type: 'rc_wheel_size', message0: '%1 set 1 wheel turn to %2 cm', style: 'rc_movement', inputsInline: true,
        args0: [iconField('bot'), num('CM')], tooltip: 'How far one turn of a wheel goes (60 mm wheel: 18.8 cm): robot.setWheelCm(18.8);' }),
      { type: 'rc_distance_moved', message0: 'distance moved (cm)', output: 'Number', style: 'rc_movement', tooltip: 'From the wheel encoders: robot.distanceCm()' },
      // ---- Motors (one wheel at a time) and servos
      stmt({ type: 'rc_motor_run', message0: '%1 run %2 motor for %3 %4', style: 'rc_motors', inputsInline: true,
        args0: [iconField('gauge'), dd('SIDE', ['left', 'right']), num('AMOUNT'), dd('UNIT', ['rotations', 'degrees', 'seconds'])],
        tooltip: 'Runs one motor and waits: motors.run(LEFT, 1, ROTATIONS);' }),
      stmt({ type: 'rc_motor_start', message0: '%1 start %2 motor at %3 %', style: 'rc_motors', inputsInline: true,
        args0: [iconField('gauge'), dd('SIDE', ['left', 'right']), num('PCT')], tooltip: 'motors.start(LEFT, 50);' }),
      stmt({ type: 'rc_motor_stop', message0: '%1 stop %2 motor', style: 'rc_motors',
        args0: [iconField('gauge'), dd('SIDE', ['left', 'right'])], tooltip: 'motors.stop(LEFT);' }),
      stmt({ type: 'rc_motor_reset', message0: '%1 reset %2 motor position', style: 'rc_motors',
        args0: [iconField('gauge'), dd('SIDE', ['left', 'right'])], tooltip: 'motors.resetPosition(LEFT);' }),
      { type: 'rc_motor_position', message0: '%1 motor position (°)', args0: [dd('SIDE', ['left', 'right'])], output: 'Number', style: 'rc_motors',
        tooltip: '360 = one wheel turn forward: motors.positionDeg(LEFT)' },
      { type: 'rc_motor_speed', message0: '%1 motor speed (%)', args0: [dd('SIDE', ['left', 'right'])], output: 'Number', style: 'rc_motors',
        tooltip: 'motors.speedPercent(LEFT)' },
      stmt({ type: 'rc_servo_set', message0: '%1 set servo %2 to %3 °', style: 'rc_motors', inputsInline: true,
        args0: [iconField('gauge'), dd('PORT', ['1', '2', '3', '4']), num('DEG')], tooltip: '0 to 180 degrees: servos.write(1, 90);' }),
      { type: 'rc_servo_angle', message0: 'servo %1 angle (°)', args0: [dd('PORT', ['1', '2', '3', '4'])], output: 'Number', style: 'rc_motors',
        tooltip: 'servos.angle(1)' },
      // ---- Light & Sound
      stmt({ type: 'rc_led', message0: 'turn LED %1', args0: [dd('STATE', [['on', 'HIGH'], ['off', 'LOW']])], style: 'rc_light',
        tooltip: 'digitalWrite(LED_BUILTIN, HIGH);' }),
      stmt({ type: 'rc_rgb', message0: 'set LED to %1', args0: [dd('COLOR', Object.keys(COLOURS))], style: 'rc_light', tooltip: 'RoboCore::rgb(255, 0, 0);' }),
      stmt({ type: 'rc_led_brightness', message0: 'set LED brightness to %1 %', args0: [num('PCT')], style: 'rc_light', inputsInline: true,
        tooltip: 'RoboCore::ledBrightness(50);' }),
      stmt({ type: 'rc_beep', message0: 'play beep %1 for %2 s', args0: [dd('NOTE', Object.keys(NOTES)), num('SECS')], style: 'rc_light', inputsInline: true,
        tooltip: 'Plays a note and waits: RoboCore::beep(523, 200);' }),
      stmt({ type: 'rc_beep_start', message0: 'start playing beep %1', args0: [dd('NOTE', Object.keys(NOTES))], style: 'rc_light',
        tooltip: 'Keeps playing until stop sound: tone(RC_PIN_BUZZER, 523);' }),
      stmt({ type: 'rc_melody', message0: 'play melody %1', args0: [dd('TUNE', Object.keys(MELODIES))], style: 'rc_light',
        tooltip: 'RoboCore::melody(MELODY_POWER_UP);' }),
      stmt({ type: 'rc_sound_stop', message0: 'stop sound', style: 'rc_light', tooltip: 'noTone(RC_PIN_BUZZER);' }),
      // ---- Sensors
      { type: 'rc_distance', message0: 'distance (cm)', output: 'Number', style: 'rc_sensors',
        tooltip: 'The ultrasonic distance sensor: sonar.distanceCm() on the RoboCore V2, distanceCm() on other boards' },
      { type: 'rc_closer', message0: 'is obstacle closer than %1 cm?', args0: [num('CM')], output: 'Boolean', style: 'rc_sensors', inputsInline: true,
        tooltip: 'distanceCm() < 20' },
      { type: 'rc_line', message0: 'line position', output: 'Number', style: 'rc_sensors', tooltip: '-1 (line on the left) to 1 (right): line.read()' },
      { type: 'rc_on_line', message0: 'is %1 sensor on the line?', args0: [dd('SENSOR', ['centre', 'left', 'right'])], output: 'Boolean', style: 'rc_sensors',
        tooltip: 'line.centre() > 0.5' },
      { type: 'rc_line_sensor', message0: '%1 line sensor (%)', args0: [dd('SENSOR', ['centre', 'left', 'right'])], output: 'Number', style: 'rc_sensors',
        tooltip: '0 white … 100 black: line.centre() * 100' },
      { type: 'rc_tilt', message0: 'tilt angle (°)', output: 'Number', style: 'rc_sensors', tooltip: 'imu.tiltDeg()' },
      { type: 'rc_angle', message0: '%1 angle (°)', args0: [dd('AXIS', ['yaw', 'pitch', 'roll'])], output: 'Number', style: 'rc_sensors',
        tooltip: 'Yaw: the heading, turning right counts up: imu.yawDeg()' },
      stmt({ type: 'rc_reset_yaw', message0: 'set yaw angle to 0', style: 'rc_sensors', tooltip: 'imu.resetYaw();' }),
      { type: 'rc_is_tilted', message0: 'is the robot %1?', args0: [dd('STATE', ['tilted', 'shaken', 'flat'])], output: 'Boolean', style: 'rc_sensors',
        tooltip: 'imu.isTilted()' },
      { type: 'rc_user_pressed', message0: 'is USER button pressed?', output: 'Boolean', style: 'rc_sensors', tooltip: 'RoboCore::userPressed()' },
      { type: 'rc_battery', message0: 'battery %1', args0: [dd('KIND', [['%', 'PERCENT'], ['volts', 'VOLTS']])], output: 'Number', style: 'rc_sensors',
        tooltip: 'RoboCore::batteryPercent()' },
      { type: 'rc_temperature', message0: 'temperature (°C)', output: 'Number', style: 'rc_sensors', tooltip: 'imu.temperature()' },
      { type: 'rc_timer', message0: 'timer (s)', output: 'Number', style: 'rc_sensors', tooltip: 'Seconds since the start or reset timer: RoboCore::timer()' },
      stmt({ type: 'rc_reset_timer', message0: 'reset timer', style: 'rc_sensors', tooltip: 'RoboCore::resetTimer();' }),
      // ---- Control
      stmt({ type: 'rc_wait', message0: 'wait %1 %2', style: 'rc_control',
        args0: [{ type: 'field_number', name: 'TIME', value: 1, min: 0 }, dd('UNIT', ['secs', 'ms'])], tooltip: 'delay(1000);' }),
      stmt({ type: 'rc_wait_until', message0: 'wait until %1', args0: [num('COND', 'Boolean')], style: 'rc_control',
        tooltip: 'while (!(condition)) delay(10);' }),
      // "repeat until ◇" as in the design (Blockly's while/until block keeps working in saved projects).
      stmt({ type: 'rc_repeat_until', message0: 'repeat until %1', args0: [num('BOOL', 'Boolean')],
        message1: '%1', args1: [{ type: 'input_statement', name: 'DO' }], style: 'rc_control', tooltip: 'while (!(condition)) { … }' }),
      { type: 'rc_stop_program', message0: 'stop program', previousStatement: null, style: 'rc_control', tooltip: 'Motors and sound off, then nothing more: RoboCore::stopProgram();' },
      // ---- Operators
      { type: 'rc_between', message0: 'is %1 between %2 and %3 ?', args0: [num('X'), num('LO'), num('HI')], output: 'Boolean', style: 'rc_operators',
        inputsInline: true, tooltip: '(x >= -10 && x <= 10)' },
      // ---- Pins & Serial
      stmt({ type: 'rc_serial_begin', message0: 'start serial at %1 baud', args0: [dd('BAUD', ['115200', '9600'])], style: 'rc_pins',
        tooltip: 'Serial.begin(115200);' }),
      stmt({ type: 'rc_print', message0: 'print %1', args0: [{ type: 'input_value', name: 'VALUE' }], style: 'rc_pins',
        tooltip: 'Sends a line to the Serial Monitor: Serial.println("…");' }),
      { type: 'rc_serial_read_line', message0: 'serial read line', output: 'String', style: 'rc_pins', tooltip: 'Serial.readStringUntil(\'\\n\')' },
      // ---- From the first block set (not in the toolbox; saved projects still use them)
      stmt({ type: 'rc_wait_button', message0: 'wait until USER is pressed', style: 'rc_control',
        tooltip: 'while (digitalRead(USER_BUTTON) == HIGH) { delay(10); }' }),
      stmt({ type: 'rc_drive', message0: '%1 drive %2 at %3 %%', style: 'rc_movement',
        args0: [iconField('bot'), dd('DIR', Object.keys(DRIVE)), { type: 'field_number', name: 'SPEED', value: 60, min: 0, max: 100, precision: 1 }],
        tooltip: 'motors.drive(left, right);' }),
      stmt({ type: 'rc_stop', message0: '%1 stop motors', args0: [iconField('bot')], style: 'rc_movement', tooltip: 'motors.stop();' }),
      stmt({ type: 'rc_print_distance', message0: 'print distance in cm', style: 'rc_sensors', tooltip: 'Serial.println(sonar.distanceCm(), 1);' }),
      stmt({ type: 'rc_print_line', message0: 'print line sensor', style: 'rc_sensors', tooltip: 'Serial.println(line.read(), 2);' }),
      stmt({ type: 'rc_print_text', message0: 'print %1', args0: [{ type: 'field_input', name: 'TEXT', text: 'Hello' }], style: 'rc_pins',
        tooltip: 'Serial.println("…");' }),
    ]);
    // Blocks whose menus are built when they open.
    Blockly.Blocks.rc_when_receive = {
      init() {
        this.appendDummyInput().appendField('when I receive').appendField(new Blockly.FieldDropdown(messageMenu, messageValidator), 'MSG');
        this.appendStatementInput('DO');
        this.setStyle('rc_events');
        this.setTooltip('Runs when another script broadcasts this message: void on_message1() { … }');
      },
    };
    Blockly.Blocks.rc_broadcast = {
      init() {
        this.appendDummyInput().appendField('broadcast').appendField(new Blockly.FieldDropdown(messageMenu, messageValidator), 'MSG');
        this.setPreviousStatement(true); this.setNextStatement(true); this.setStyle('rc_events');
        this.setTooltip('Runs the “when I receive” scripts for this message, then carries on: on_message1();');
      },
    };
    const readPin = (type, label, tooltip, list) => {
      Blockly.Blocks[type] = {
        init() {
          this.appendDummyInput().appendField(label).appendField(new Blockly.FieldDropdown(pinMenu(list)), 'PIN');
          this.setOutput(true, 'Number');
          this.setStyle('rc_pins');
          this.setTooltip(tooltip);
        },
      };
    };
    readPin('rc_read_pin', 'read pin', 'HIGH (1) or LOW (0): digitalRead(pin)', 'pins');
    readPin('rc_read_analog', 'read analog pin', '0 to 4095 on the RoboCore V2 (0 to 1023 on an Uno): analogRead(pin)', 'analogPins');
    Blockly.Blocks.rc_pin = {
      init() {
        this.appendDummyInput().appendField('set pin').appendField(new Blockly.FieldDropdown(pinMenu('pins')), 'PIN')
          .appendField('to').appendField(new Blockly.FieldDropdown(dropdown(['HIGH', 'LOW'])), 'STATE');
        this.setPreviousStatement(true); this.setNextStatement(true); this.setStyle('rc_pins');
        this.setTooltip('digitalWrite(pin, HIGH);');
      },
    };
    // Where an HC-SR04 distance sensor is wired on an Uno or an ESP32 board (the RoboCore V2's sonar port is fixed).
    // It starts on pins that are free on that board; a saved project keeps its own.
    Blockly.Blocks.rc_sonar_pins = {
      init() {
        this.appendDummyInput().appendField('distance sensor on TRIG pin').appendField(new Blockly.FieldDropdown(pinMenu('pins')), 'TRIG')
          .appendField('ECHO pin').appendField(new Blockly.FieldDropdown(pinMenu('pins')), 'ECHO');
        const [trig, echo] = sonarDefaults();
        this.setFieldValue(trig, 'TRIG');
        this.setFieldValue(echo, 'ECHO');
        this.setPreviousStatement(true); this.setNextStatement(true); this.setStyle('rc_sensors');
        this.setTooltip('Put it in "on start": the pins the sensor\'s TRIG and ECHO wires go to. The RoboCore V2 has its own sonar port, so it does not need this block.');
      },
    };
    // From the first block set: a tone on a chosen pin.
    Blockly.Blocks.rc_tone = {
      init() {
        this.appendDummyInput().appendField('tone pin').appendField(new Blockly.FieldDropdown(pinMenu('tonePins')), 'PIN')
          .appendField(new Blockly.FieldDropdown(dropdown(Object.keys(NOTES))), 'NOTE')
          .appendField('for').appendField(new Blockly.FieldNumber(0.5, 0), 'SECS').appendField('s');
        this.setPreviousStatement(true); this.setNextStatement(true); this.setStyle('rc_light');
        this.setTooltip('tone(pin, frequency, ms); delay(ms);');
      },
    };
    // Blockly's own blocks, in the RoboCore categories.
    const restyle = (type, style) => {
      const init = Blockly.Blocks[type].init;
      Blockly.Blocks[type].init = function () { init.call(this); this.setStyle(style); };
    };
    for (const t of ['logic_compare', 'logic_operation', 'logic_negate', 'logic_boolean', 'math_number', 'math_arithmetic',
      'math_random_int', 'math_round', 'text']) restyle(t, 'rc_operators');
    for (const t of ['controls_if', 'controls_repeat_ext', 'controls_whileUntil']) restyle(t, 'rc_control');
    // "if ◇ then" on one row, as in the design: "then" follows each condition (else if too), not the mouth below.
    const thenAfterIf = (b) => {
      for (let i = 0; b.getInput('IF' + i); i++) {
        if (b.getInput('THEN' + i)) continue;
        b.appendDummyInput('THEN' + i).appendField('then');
        b.moveInputBefore('THEN' + i, 'DO' + i);
      }
    };
    const ifInit = Blockly.Blocks.controls_if.init;
    Blockly.Blocks.controls_if.init = function () {
      ifInit.call(this);
      this.setInputsInline(true);
      const shape = this.updateShape_;
      this.updateShape_ = function () {
        for (let i = 1; this.getInput('THEN' + i); i++) this.removeInput('THEN' + i);
        shape.call(this);
        thenAfterIf(this);
      };
      thenAfterIf(this);
    };
    // Their words, as in the catalogue (no "do" beside the mouths).
    Object.assign(Blockly.Msg, {
      CONTROLS_IF_MSG_THEN: '',
      CONTROLS_REPEAT_INPUT_DO: '',
      MATH_RANDOM_INT_TITLE: 'pick random %1 to %2',
      TEXT_JOIN_TITLE_CREATEWITH: 'join',
      PROCEDURES_DEFNORETURN_TITLE: 'define',
      PROCEDURES_DEFNORETURN_PROCEDURE: 'my block',
      PROCEDURES_BEFORE_PARAMS: 'with:',
      NEW_VARIABLE: 'Make a variable…',
    });
  }

  // The toolbox: the 10 categories, with each block's starting values.
  const num = (v) => ({ shadow: { type: 'math_number', fields: { NUM: v } } });
  const txt = (v) => ({ shadow: { type: 'text', fields: { TEXT: v } } });
  const blk = (type, inputs, extra) => Object.assign({ kind: 'block', type }, inputs ? { inputs } : {}, extra || {});
  // Each flyout starts with its category's title (the design's swatch + name; see decorateFlyout).
  const title = (key) => ({ kind: 'label', text: CATS.find((x) => x[0] === key)[1].toUpperCase(), 'web-class': 'rcFlyoutTitle rcTitle_' + key });
  const category = (key, contents, custom) => {
    const c = CATS.find((x) => x[0] === key);
    return Object.assign({ kind: 'category', name: c[1], categorystyle: key, cssConfig: { icon: 'rcCatIcon rcCat_' + key } },
      custom ? { custom } : { contents: [title(key), ...contents] });
  };
  const TOOLBOX = {
    kind: 'categoryToolbox',
    contents: [
      category('events', [
        blk('rc_on_start'), blk('rc_forever'), blk('rc_when_user'), blk('rc_when_closer', { CM: num(20) }), blk('rc_when_line'),
        blk('rc_when_tilt'), blk('rc_when_timer', { SECS: num(10) }), blk('rc_when'), blk('rc_when_receive'), blk('rc_broadcast')]),
      category('movement', [
        blk('rc_move', { AMOUNT: num(10) }), blk('rc_turn', { DEG: num(90) }), blk('rc_start_moving'), blk('rc_steer', { STEER: num(30) }),
        blk('rc_drive_lr', { L: num(50), R: num(50) }), blk('rc_stop_moving'), blk('rc_move_speed', { PCT: num(50) }),
        blk('rc_wheel_size', { CM: num(18.8) }), blk('rc_distance_moved')]),
      category('motors', [
        blk('rc_motor_run', { AMOUNT: num(1) }), blk('rc_motor_start', { PCT: num(50) }), blk('rc_motor_stop'), blk('rc_motor_reset'),
        blk('rc_motor_position'), blk('rc_motor_speed'), blk('rc_servo_set', { DEG: num(90) }), blk('rc_servo_angle')]),
      category('light', [
        blk('rc_led'), blk('rc_rgb'), blk('rc_led_brightness', { PCT: num(50) }), blk('rc_beep', null, { fields: { NOTE: 'C5' }, inputs: { SECS: num(0.2) } }),
        blk('rc_beep_start', null, { fields: { NOTE: 'C5' } }), blk('rc_melody'), blk('rc_sound_stop')]),
      category('sensors', [
        blk('rc_sonar_pins'), blk('rc_distance'), blk('rc_closer', { CM: num(20) }), blk('rc_line'), blk('rc_on_line'), blk('rc_line_sensor'), blk('rc_tilt'),
        blk('rc_angle'), blk('rc_reset_yaw'), blk('rc_is_tilted'), blk('rc_user_pressed'), blk('rc_battery'), blk('rc_temperature'),
        blk('rc_timer'), blk('rc_reset_timer')]),
      category('control', [
        blk('rc_wait'), blk('controls_repeat_ext', { TIMES: num(5) }), blk('controls_if'), blk('controls_if', null, { extraState: { hasElse: true } }),
        blk('rc_wait_until'), blk('rc_repeat_until'), blk('rc_stop_program')]),
      category('operators', [
        blk('math_arithmetic', { A: num(0), B: num(0) }), blk('logic_compare', { A: num(0), B: num(20) }, { fields: { OP: 'LT' } }),
        blk('logic_operation'), blk('logic_negate'), blk('math_random_int', { FROM: num(1), TO: num(10) }),
        blk('rc_between', { X: num(0), LO: num(-10), HI: num(10) }), blk('math_round', { NUM: num(3.6) }),
        blk('text_join', { ADD0: txt('cm: '), ADD1: txt('20') })]),
      category('variables', null, 'RC_VARIABLES'),
      category('myblocks', null, 'RC_MYBLOCKS'),
      category('pins', [
        blk('rc_pin'), blk('rc_read_pin'), blk('rc_read_analog'), blk('rc_serial_begin'),
        blk('rc_print', { VALUE: txt('RoboCore V2 ready') }), blk('rc_serial_read_line')]),
    ],
  };

  // My Blocks: Make a block… and a call block for each block made (Blockly's procedures, no return value).
  function registerMyBlocks(w) {
    w.registerToolboxCategoryCallback('RC_VARIABLES', (ws) => [title('variables'), ...Blockly.Variables.flyoutCategory(ws)]);
    w.registerToolboxCategoryCallback('RC_MYBLOCKS', (ws) => {
      const items = [title('myblocks'), { kind: 'button', text: 'Make a block…', callbackkey: 'rcMakeBlock' }];
      for (const [name, params] of Blockly.Procedures.allProcedures(ws)[0]) {
        items.push({ kind: 'block', type: 'procedures_callnoreturn', extraState: { name, params } });
      }
      return items;
    });
    w.registerButtonCallback('rcMakeBlock', () => {
      Blockly.dialog.prompt('Name of the new block:', '', (name) => {
        const n = (name || '').trim();
        if (!n) return;
        const b = w.newBlock('procedures_defnoreturn');
        b.setFieldValue(Blockly.Procedures.findLegalName(n, b), 'NAME');
        b.initSvg();
        b.render();
        const m = w.getMetricsManager().getViewMetrics(true);
        b.moveTo(new Blockly.utils.Coordinate(m.left + 40, m.top + 40));
        b.select();
      });
    });
  }

  // ---------------------------------------------------------------- Arduino C++ generator

  const O = { ATOMIC: 0, POSTFIX: 2, PREFIX: 3, MULT: 5, ADD: 6, REL: 8, EQ: 9, AND: 13, OR: 14, NONE: 99 };
  let cpp = null;

  const toNum = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
  const toInt = (v) => Math.trunc(toNum(v));
  // A pin in the C++: its number, or A0 … A5 for an Uno's analog pins (14 to 19).
  const pinCode = (v) => {
    const n = toInt(v);
    return isUnoAnalog(n) ? 'A' + (n - 14) : String(n);
  };
  const cstr = (s) => String(s == null ? '' : s).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  const fmt = (n) => (Number.isInteger(n) ? String(n) : String(+n.toFixed(6)));
  const isLiteral = (code) => /^-?\d+(\.\d+)?$/.test(code);
  // -x for "backward" / "left": -10 for a number, -(x) for anything else.
  const neg = (code) => (isLiteral(code) ? fmt(-toNum(code)) : '-(' + code + ')');
  // Seconds → milliseconds: 200 for 0.2, (x) * 1000 for anything else.
  const ms = (code) => (isLiteral(code) ? String(Math.max(0, Math.round(toNum(code) * 1000))) : '(' + code + ') * 1000');
  const SIDE = (b) => (b.getFieldValue('SIDE') === 'right' ? 'RIGHT' : 'LEFT');
  // "blink twice" → blinkTwice; "message1" → on_message1.
  const camel = (s) => {
    const w = String(s).replace(/[^A-Za-z0-9]+/g, ' ').trim().split(/\s+/).filter(Boolean);
    const id = w.map((x, i) => (i ? x[0].toUpperCase() + x.slice(1) : x[0].toLowerCase() + x.slice(1))).join('') || 'myBlock';
    return /^\d/.test(id) ? 'b' + id : id;
  };
  const handler = (msg) => 'on_' + (String(msg).replace(/[^A-Za-z0-9]+/g, '_').replace(/^_+|_+$/g, '') || 'message');

  function makeGenerator() {
    const g = new Blockly.CodeGenerator('ArduinoCpp');
    g.INDENT = '  ';
    // A variable a student calls "word" or "delay" gets another name (word2): these mean something already.
    g.addReservedWords(
      // C++
      'alignas,alignof,and,asm,auto,bool,break,case,catch,char,class,const,constexpr,continue,default,delete,do,double,else,enum,' +
      'explicit,export,extern,false,float,for,friend,goto,if,inline,int,long,mutable,namespace,new,noexcept,not,nullptr,operator,or,' +
      'private,protected,public,register,return,short,signed,sizeof,static,struct,switch,template,this,throw,true,try,typedef,typename,' +
      'union,unsigned,using,virtual,void,volatile,while,xor,' +
      // Arduino
      'setup,loop,Serial,Wire,String,byte,word,boolean,size_t,HIGH,LOW,INPUT,OUTPUT,INPUT_PULLUP,LED_BUILTIN,RGB_BUILTIN,PI,HALF_PI,' +
      'TWO_PI,DEG_TO_RAD,RAD_TO_DEG,pinMode,digitalWrite,digitalRead,analogRead,analogWrite,delay,delayMicroseconds,millis,micros,' +
      'tone,noTone,random,randomSeed,map,min,max,abs,constrain,round,sq,sqrt,pow,sin,cos,tan,floor,ceil,bit,bitRead,bitWrite,' +
      'highByte,lowByte,interrupts,noInterrupts,attachInterrupt,detachInterrupt,yield,rgbLedWrite,' +
      // RoboCore and the names the blocks use
      'RoboCore,RoboCoreMotors,RoboCoreDrive,RoboCoreServos,RoboCoreEdge,Sonar,LineSensor,IMU,motors,sonar,line,imu,robot,servos,' +
      'LEFT,RIGHT,FORWARD,BACKWARD,CM,ROTATIONS,DEGREES,SECONDS,MELODY_POWER_UP,MELODY_POWER_DOWN,MELODY_SUCCESS,MELODY_ERROR,' +
      'MELODY_ALARM,USER_BUTTON,when1,when2,when3,when4,when5,when6,when7,when8,when9');
    g.init = function (ws) {
      Object.getPrototypeOf(g).init.call(this, ws);
      if (!this.nameDB_) this.nameDB_ = new Blockly.Names(this.RESERVED_WORDS_);
      else this.nameDB_.reset();
      this.nameDB_.setVariableMap(ws.getVariableMap());
      this.nameDB_.populateVariables(ws);
    };
    g.finish = (code) => code;
    g.scrubNakedValue = (line) => line + ';\n';
    g.scrub_ = function (block, code, thisOnly) {
      const next = block.nextConnection && block.nextConnection.targetBlock();
      return thisOnly || !next ? code : code + this.blockToCode(next);
    };
    const varName = (block) => g.nameDB_.getName(block.getFieldValue('VAR'), Blockly.Names.NameType.VARIABLE);
    const val = (b, name, order, def) => g.valueToCode(b, name, order) || def;
    const v2 = () => CTX.board === 'v2';
    const tonePin = () => (v2() ? 'RC_PIN_BUZZER' : String(toInt(CTX.tonePins[0] || 8)));
    const f = g.forBlock;

    // Script tops: their bodies are placed by generate().
    for (const t of HATS) f[t] = () => '';
    f.procedures_defnoreturn = () => '';

    // Events
    f.rc_broadcast = (b) => handler(b.getFieldValue('MSG')) + '();\n';
    // Movement
    f.rc_move = (b) => {
      const a = val(b, 'AMOUNT', O.NONE, '0'), unit = { rotations: 'ROTATIONS', seconds: 'SECONDS' }[b.getFieldValue('UNIT')] || 'CM';
      return 'robot.move(' + (b.getFieldValue('DIR') === 'backward' ? neg(a) : a) + ', ' + unit + ');\n';
    };
    f.rc_turn = (b) => { const d = val(b, 'DEG', O.NONE, '0'); return 'robot.turn(' + (b.getFieldValue('DIR') === 'left' ? neg(d) : d) + ');\n'; };
    f.rc_start_moving = (b) => 'robot.start(' + (b.getFieldValue('DIR') === 'backward' ? 'BACKWARD' : 'FORWARD') + ');\n';
    f.rc_steer = (b) => 'robot.steer(' + val(b, 'STEER', O.NONE, '0') + ');\n';
    f.rc_drive_lr = (b) => 'motors.drive(' + val(b, 'L', O.NONE, '0') + ', ' + val(b, 'R', O.NONE, '0') + ');\n';
    f.rc_stop_moving = () => 'robot.stop();\n';
    f.rc_move_speed = (b) => 'robot.setSpeed(' + val(b, 'PCT', O.NONE, '50') + ');\n';
    f.rc_wheel_size = (b) => 'robot.setWheelCm(' + val(b, 'CM', O.NONE, '18.8') + ');\n';
    f.rc_distance_moved = () => ['robot.distanceCm()', O.POSTFIX];
    // Motors
    f.rc_motor_run = (b) => {
      const unit = { degrees: 'DEGREES', seconds: 'SECONDS' }[b.getFieldValue('UNIT')] || 'ROTATIONS';
      return 'motors.run(' + SIDE(b) + ', ' + val(b, 'AMOUNT', O.NONE, '0') + ', ' + unit + ');\n';
    };
    f.rc_motor_start = (b) => 'motors.start(' + SIDE(b) + ', ' + val(b, 'PCT', O.NONE, '0') + ');\n';
    f.rc_motor_stop = (b) => 'motors.stop(' + SIDE(b) + ');\n';
    f.rc_motor_reset = (b) => 'motors.resetPosition(' + SIDE(b) + ');\n';
    f.rc_motor_position = (b) => ['motors.positionDeg(' + SIDE(b) + ')', O.POSTFIX];
    f.rc_motor_speed = (b) => ['motors.speedPercent(' + SIDE(b) + ')', O.POSTFIX];
    f.rc_servo_set = (b) => 'servos.write(' + toInt(b.getFieldValue('PORT')) + ', ' + val(b, 'DEG', O.NONE, '90') + ');\n';
    f.rc_servo_angle = (b) => ['servos.angle(' + toInt(b.getFieldValue('PORT')) + ')', O.POSTFIX];
    // Light & Sound
    f.rc_led = (b) => 'digitalWrite(LED_BUILTIN, ' + (b.getFieldValue('STATE') === 'LOW' ? 'LOW' : 'HIGH') + ');\n';
    f.rc_rgb = (b) => {
      const name = b.getFieldValue('COLOR'), c = COLOURS[name] || COLOURS.off;
      return (v2() ? 'RoboCore::rgb(' : 'rgbLedWrite(RGB_BUILTIN, ') + c.join(', ') + ');  // ' + name + '\n';
    };
    f.rc_led_brightness = (b) => 'RoboCore::ledBrightness(' + val(b, 'PCT', O.NONE, '100') + ');\n';
    f.rc_beep = (b) => {
      const note = b.getFieldValue('NOTE'), hz = NOTES[note] || 523, d = ms(val(b, 'SECS', O.MULT, '0'));
      if (v2()) return 'RoboCore::beep(' + hz + ', ' + d + ');  // ' + note + '\n';
      return 'tone(' + tonePin() + ', ' + hz + ', ' + d + ');  // ' + note + '\ndelay(' + d + ');\n';
    };
    f.rc_beep_start = (b) => 'tone(' + tonePin() + ', ' + (NOTES[b.getFieldValue('NOTE')] || 523) + ');  // ' + b.getFieldValue('NOTE') + '\n';
    f.rc_melody = (b) => 'RoboCore::melody(' + (MELODIES[b.getFieldValue('TUNE')] || 'MELODY_POWER_UP') + ');\n';
    f.rc_sound_stop = () => 'noTone(' + tonePin() + ');\n';
    // Sensors
    // The RoboCore V2's sonar port (the RoboCore library); elsewhere a distanceCm() written into the sketch.
    const distance = () => (v2() ? 'sonar.distanceCm()' : 'distanceCm()');
    f.rc_sonar_pins = () => '';
    f.rc_distance = () => [distance(), O.POSTFIX];
    f.rc_closer = (b) => [distance() + ' < ' + val(b, 'CM', O.REL, '20'), O.REL];
    f.rc_line = () => ['line.read()', O.POSTFIX];
    f.rc_on_line = (b) => ['line.' + (b.getFieldValue('SENSOR') || 'centre') + '() > 0.5', O.REL];
    f.rc_line_sensor = (b) => ['line.' + (b.getFieldValue('SENSOR') || 'centre') + '() * 100', O.MULT];
    f.rc_tilt = () => ['imu.tiltDeg()', O.POSTFIX];
    f.rc_angle = (b) => ['imu.' + (b.getFieldValue('AXIS') || 'yaw') + 'Deg()', O.POSTFIX];
    f.rc_reset_yaw = () => 'imu.resetYaw();\n';
    f.rc_is_tilted = (b) => ['imu.' + ({ shaken: 'isShaken', flat: 'isFlat' }[b.getFieldValue('STATE')] || 'isTilted') + '()', O.POSTFIX];
    f.rc_user_pressed = () => (v2() ? ['RoboCore::userPressed()', O.POSTFIX] : ['digitalRead(USER_BUTTON) == LOW', O.EQ]);
    f.rc_battery = (b) => [b.getFieldValue('KIND') === 'VOLTS' ? 'RoboCore::batteryVolts()' : 'RoboCore::batteryPercent()', O.POSTFIX];
    f.rc_temperature = () => ['imu.temperature()', O.POSTFIX];
    f.rc_timer = () => ['RoboCore::timer()', O.POSTFIX];
    f.rc_reset_timer = () => 'RoboCore::resetTimer();\n';
    // Control
    f.rc_wait = (b) => {
      const d = Math.round(toNum(b.getFieldValue('TIME')) * (b.getFieldValue('UNIT') === 'ms' ? 1 : 1000));
      return 'delay(' + Math.max(0, d) + ');\n';
    };
    f.rc_wait_until = (b) => 'while (!(' + val(b, 'COND', O.NONE, 'false') + ')) {\n  delay(10);\n}\n';
    f.rc_stop_program = () => (v2() ? 'RoboCore::stopProgram();\n' : 'while (true) {\n  delay(1000);\n}\n');
    // Operators
    f.rc_between = (b) => {
      const x = val(b, 'X', O.REL, '0');
      return [x + ' >= ' + val(b, 'LO', O.REL, '0') + ' && ' + x + ' <= ' + val(b, 'HI', O.REL, '0'), O.AND];
    };
    // Pins & Serial
    f.rc_pin = (b) => 'digitalWrite(' + pinCode(b.getFieldValue('PIN')) + ', ' + (b.getFieldValue('STATE') === 'LOW' ? 'LOW' : 'HIGH') + ');\n';
    f.rc_read_pin = (b) => ['digitalRead(' + pinCode(b.getFieldValue('PIN')) + ')', O.POSTFIX];
    f.rc_read_analog = (b) => ['analogRead(' + pinCode(b.getFieldValue('PIN')) + ')', O.POSTFIX];
    f.rc_serial_begin = (b) => 'Serial.begin(' + (b.getFieldValue('BAUD') === '9600' ? 9600 : 115200) + ');\n';
    f.rc_print = (b) => 'Serial.println(' + val(b, 'VALUE', O.NONE, '""') + ');\n';
    f.rc_serial_read_line = () => ["Serial.readStringUntil('\\n')", O.POSTFIX];
    // From the first block set
    f.rc_wait_button = () => 'while (digitalRead(USER_BUTTON) == HIGH) {\n  delay(10);\n}\n';
    f.rc_drive = (b) => {
      const s = Math.trunc(Math.min(100, Math.max(0, toNum(b.getFieldValue('SPEED'))))), m = DRIVE[b.getFieldValue('DIR')] || DRIVE.forward;
      return 'motors.drive(' + m[0] * s + ', ' + m[1] * s + ');\n';
    };
    f.rc_stop = () => 'motors.stop();\n';
    f.rc_print_distance = () => 'Serial.print("distance_cm=");\nSerial.println(' + distance() + ', 1);\n';
    f.rc_print_line = () => 'Serial.print("line=");\nSerial.println(line.read(), 2);\n';
    f.rc_print_text = (b) => 'Serial.println("' + cstr(b.getFieldValue('TEXT')) + '");\n';
    f.rc_tone = (b) => {
      const d = Math.max(0, Math.round(toNum(b.getFieldValue('SECS')) * 1000)), note = b.getFieldValue('NOTE');
      return 'tone(' + pinCode(b.getFieldValue('PIN')) + ', ' + (NOTES[note] || 262) + ', ' + d + ');  // ' + note + '\ndelay(' + d + ');\n';
    };

    // Blockly's own blocks in C++.
    f.controls_if = (b) => {
      let code = '', n = 0;
      do {
        const cond = g.valueToCode(b, 'IF' + n, O.NONE) || 'false';
        code += (n ? ' else if (' : 'if (') + cond + ') {\n' + g.statementToCode(b, 'DO' + n) + '}';
        n++;
      } while (b.getInput('IF' + n));
      if (b.getInput('ELSE')) code += ' else {\n' + g.statementToCode(b, 'ELSE') + '}';
      return code + '\n';
    };
    f.controls_repeat_ext = (b) => {
      const times = g.valueToCode(b, 'TIMES', O.REL) || '0';
      const i = g.nameDB_.getDistinctName('i', Blockly.Names.NameType.VARIABLE);
      return 'for (int ' + i + ' = 0; ' + i + ' < ' + times + '; ' + i + '++) {\n' + g.statementToCode(b, 'DO') + '}\n';
    };
    f.controls_whileUntil = (b) => {
      const until = b.getFieldValue('MODE') === 'UNTIL';
      let cond = g.valueToCode(b, 'BOOL', until ? O.PREFIX : O.NONE) || 'false';
      if (until) cond = '!' + cond;
      return 'while (' + cond + ') {\n' + g.statementToCode(b, 'DO') + '}\n';
    };
    f.rc_repeat_until = (b) => 'while (!' + (g.valueToCode(b, 'BOOL', O.PREFIX) || 'false') + ') {\n' + g.statementToCode(b, 'DO') + '}\n';
    f.logic_compare = (b) => {
      const op = { EQ: '==', NEQ: '!=', LT: '<', LTE: '<=', GT: '>', GTE: '>=' }[b.getFieldValue('OP')];
      const order = op === '==' || op === '!=' ? O.EQ : O.REL;
      return [(g.valueToCode(b, 'A', order) || '0') + ' ' + op + ' ' + (g.valueToCode(b, 'B', order) || '0'), order];
    };
    f.logic_operation = (b) => {
      const and = b.getFieldValue('OP') === 'AND', order = and ? O.AND : O.OR;
      return [(g.valueToCode(b, 'A', order) || 'false') + (and ? ' && ' : ' || ') + (g.valueToCode(b, 'B', order) || 'false'), order];
    };
    f.logic_negate = (b) => ['!' + (g.valueToCode(b, 'BOOL', O.PREFIX) || 'true'), O.PREFIX];
    f.logic_boolean = (b) => [b.getFieldValue('BOOL') === 'TRUE' ? 'true' : 'false', O.ATOMIC];
    f.math_number = (b) => {
      const n = toNum(b.getFieldValue('NUM'));
      return [fmt(n), n < 0 ? O.PREFIX : O.ATOMIC];
    };
    f.math_arithmetic = (b) => {
      const op = b.getFieldValue('OP');
      if (op === 'POWER') return ['pow(' + (g.valueToCode(b, 'A', O.NONE) || '0') + ', ' + (g.valueToCode(b, 'B', O.NONE) || '0') + ')', O.POSTFIX];
      const [sym, order] = { ADD: [' + ', O.ADD], MINUS: [' - ', O.ADD], MULTIPLY: [' * ', O.MULT], DIVIDE: [' / ', O.MULT] }[op];
      return [(g.valueToCode(b, 'A', order) || '0') + sym + (g.valueToCode(b, 'B', order + 0.5) || '0'), order];
    };
    // random(a, b + 1) like the old "random" block; a literal top bound is added up front.
    f.math_random_int = (b) => {
      const from = g.valueToCode(b, 'FROM', O.NONE) || '0', to = g.valueToCode(b, 'TO', O.ADD) || '0';
      const top = /^-?\d+$/.test(to) ? String(parseInt(to, 10) + 1) : to + ' + 1';
      return ['random(' + from + ', ' + top + ')', O.POSTFIX];
    };
    f.math_round = (b) => [({ ROUNDUP: 'ceil', ROUNDDOWN: 'floor' }[b.getFieldValue('OP')] || 'round') + '(' + val(b, 'NUM', O.NONE, '0') + ')', O.POSTFIX];
    f.text = (b) => ['"' + cstr(b.getFieldValue('TEXT')) + '"', O.ATOMIC];
    f.text_join = (b) => {
      const parts = [];
      for (let i = 0; b.getInput('ADD' + i); i++) parts.push(g.valueToCode(b, 'ADD' + i, O.ADD) || '""');
      if (!parts.length) return ['String("")', O.POSTFIX];
      return ['String(' + parts[0] + ')' + parts.slice(1).map((p) => ' + ' + p).join(''), O.ADD];
    };
    f.variables_get = (b) => [varName(b), O.ATOMIC];
    f.variables_set = (b) => varName(b) + ' = ' + (g.valueToCode(b, 'VALUE', O.NONE) || '0') + ';\n';
    f.math_change = (b) => varName(b) + ' += ' + (g.valueToCode(b, 'DELTA', O.NONE) || '0') + ';\n';
    f.procedures_callnoreturn = (b) => {
      const args = [];
      for (let i = 0; b.getInput('ARG' + i); i++) args.push(g.valueToCode(b, 'ARG' + i, O.NONE) || '0');
      return camel(b.getFieldValue('NAME')) + '(' + args.join(', ') + ');\n';
    };
    return g;
  }

  function live(b) {
    return b.isEnabled() && !(typeof b.getInheritedDisabled === 'function' && b.getInheritedDisabled());
  }

  // Variable types: int when every value given to it is a whole number, String for text, else float.
  const INT_BLOCKS = new Set(['math_random_int', 'math_round', 'rc_read_pin', 'rc_read_analog', 'rc_motor_speed']);
  const STRING_BLOCKS = new Set(['text', 'text_join', 'rc_serial_read_line']);
  function varTypes(blocks) {
    const sets = new Map(); // variable id → value blocks given to it
    for (const b of blocks) {
      if (b.type !== 'variables_set' && b.type !== 'math_change') continue;
      const id = b.getFieldValue('VAR');
      if (!sets.has(id)) sets.set(id, []);
      sets.get(id).push(b.getInputTargetBlock(b.type === 'math_change' ? 'DELTA' : 'VALUE'));
    }
    const types = new Map();
    const kind = (b, seen) => {
      if (!b) return 'int';
      if (STRING_BLOCKS.has(b.type)) return 'String';
      if (INT_BLOCKS.has(b.type)) return 'int';
      if (b.type === 'math_number') return Number.isInteger(toNum(b.getFieldValue('NUM'))) ? 'int' : 'float';
      if (b.type === 'rc_battery') return b.getFieldValue('KIND') === 'VOLTS' ? 'float' : 'int';
      if (b.type === 'variables_get') return typeOf(b.getFieldValue('VAR'), seen);
      if (b.type === 'math_arithmetic') {
        if (['DIVIDE', 'POWER'].includes(b.getFieldValue('OP'))) return 'float';
        const a = kind(b.getInputTargetBlock('A'), seen), c = kind(b.getInputTargetBlock('B'), seen);
        return a === 'String' || c === 'String' ? 'String' : a === 'float' || c === 'float' ? 'float' : 'int';
      }
      return 'float';
    };
    const typeOf = (id, seen = new Set()) => {
      if (types.has(id)) return types.get(id);
      if (seen.has(id)) return 'int';
      seen.add(id);
      const ks = (sets.get(id) || []).map((b) => kind(b, seen));
      return ks.includes('String') ? 'String' : ks.includes('float') ? 'float' : 'int';
    };
    for (const id of sets.keys()) types.set(id, typeOf(id));
    return types;
  }

  // The whole sketch: includes, globals, My Blocks and messages, setup, loop.
  function generate(ws) {
    cpp.init(ws);
    const tops = ws.getTopBlocks(true).filter((b) => isRoot(b.type) && live(b));
    const blocks = [];
    for (const t of tops) for (const b of t.getDescendants(true)) if (live(b)) blocks.push(b);
    const used = new Set(blocks.map((b) => b.type));
    const has = (...t) => t.some((x) => used.has(x));
    const v2 = CTX.board === 'v2';
    const add = (list, v) => { if (!list.includes(v)) list.push(v); };

    // Variables, and the parameters of My Blocks (those are not globals).
    const params = new Set();
    for (const t of tops) if (t.type === 'procedures_defnoreturn' && t.getVarModels) for (const m of t.getVarModels()) params.add(m.getId());
    const types = varTypes(blocks), vars = [];
    for (const b of blocks) {
      if (!['variables_set', 'variables_get', 'math_change'].includes(b.type)) continue;
      const id = b.getFieldValue('VAR');
      if (params.has(id)) continue;
      add(vars, id);
    }
    const outPins = [], inPins = [];
    for (const b of blocks) {
      if (b.type === 'rc_pin') add(outPins, pinCode(b.getFieldValue('PIN')));
      if (b.type === 'rc_read_pin') add(inPins, pinCode(b.getFieldValue('PIN')));
      if (b.type === 'rc_tone') add(outPins, pinCode(b.getFieldValue('PIN')));
    }

    const usesRobot = has('rc_move', 'rc_turn', 'rc_start_moving', 'rc_steer', 'rc_stop_moving', 'rc_move_speed', 'rc_wheel_size', 'rc_distance_moved');
    const usesMot = usesRobot || has('rc_drive_lr', 'rc_motor_run', 'rc_motor_start', 'rc_motor_stop', 'rc_motor_reset', 'rc_motor_position', 'rc_motor_speed', 'rc_drive', 'rc_stop');
    const usesSonar = has('rc_distance', 'rc_closer', 'rc_when_closer', 'rc_print_distance');
    const usesLine = has('rc_line', 'rc_on_line', 'rc_line_sensor', 'rc_when_line', 'rc_print_line');
    const imuBlocks = has('rc_tilt', 'rc_angle', 'rc_reset_yaw', 'rc_is_tilted', 'rc_temperature', 'rc_when_tilt');
    const usesImu = usesRobot || imuBlocks;
    const usesServos = has('rc_servo_set', 'rc_servo_angle');
    const edges = tops.filter((t) => t.type === 'rc_when');
    const usesLib = usesMot || (usesSonar && v2) || usesLine || usesImu || usesServos || edges.length > 0 ||
      has('rc_led_brightness', 'rc_melody', 'rc_battery', 'rc_timer', 'rc_reset_timer', 'rc_when_user', 'rc_when_timer', 'rc_stop_program') ||
      (v2 && has('rc_rgb', 'rc_beep', 'rc_beep_start', 'rc_sound_stop', 'rc_user_pressed'));
    const usesBtnPin = has('rc_wait_button') || (!v2 && has('rc_user_pressed'));
    const needSerial = has('rc_print', 'rc_print_text', 'rc_print_distance', 'rc_print_line', 'rc_serial_read_line') && !has('rc_serial_begin');

    const body = (t) => cpp.statementToCode(t, 'DO');
    const ind = (code) => code.replace(/^(?=.)/gm, '  ');

    // The "when …" hats, checked at the top of loop() in the order they sit on the workspace.
    let n = 0;
    const whenCode = [];
    const ordered = tops.slice().sort((a, b) => a.getRelativeToSurfaceXY().y - b.getRelativeToSurfaceXY().y || a.getRelativeToSurfaceXY().x - b.getRelativeToSurfaceXY().x);
    const edgeName = new Map();
    for (const t of ordered) {
      if (t.type === 'rc_when') edgeName.set(t.id, 'when' + (++n));
      const cond = whenCond(t, edgeName.get(t.id));
      if (cond) whenCode.push('if (' + cond + ') {\n' + body(t) + '}');
    }

    // My Blocks and messages become functions.
    const fns = [];
    for (const t of ordered.filter((x) => x.type === 'procedures_defnoreturn')) {
      const ps = (t.getVarModels ? t.getVarModels() : []).map((m) => 'float ' + cpp.nameDB_.getName(m.getId(), Blockly.Names.NameType.VARIABLE));
      fns.push(['void ' + camel(t.getFieldValue('NAME')) + '(' + ps.join(', ') + ')', cpp.statementToCode(t, 'STACK')]);
    }
    const msgs = new Map();
    for (const t of ordered.filter((x) => x.type === 'rc_when_receive')) {
      const h = handler(t.getFieldValue('MSG'));
      msgs.set(h, (msgs.get(h) || '') + body(t));
    }
    for (const b of blocks.filter((x) => x.type === 'rc_broadcast')) {
      const h = handler(b.getFieldValue('MSG'));
      if (!msgs.has(h)) msgs.set(h, '');
    }
    for (const [h, code] of msgs) fns.push(['void ' + h + '()', code]);

    const l = ['// ' + CTX.name, '// Made with blocks in RoboCore IDE.', ''];
    if (usesLib) l.push('#include <RoboCore.h>');
    if (usesBtnPin) l.push(v2 ? '#define USER_BUTTON ' + CTX.userPin : '#define USER_BUTTON 0');
    // Some ESP32 board packages have no LED_BUILTIN.
    if (!v2 && has('rc_led')) l.push('#ifndef LED_BUILTIN', '#define LED_BUILTIN ' + toInt(CTX.led), '#endif');
    const glob = [];
    if (usesMot) glob.push('RoboCoreMotors motors;');
    if (usesSonar && v2) glob.push('Sonar sonar;');
    // Other boards: an HC-SR04 on the pins of the "distance sensor" block, read with plain Arduino code.
    const sonarPins = blocks.find((b) => b.type === 'rc_sonar_pins');
    const [trig, echo] = sonarPins ? [sonarPins.getFieldValue('TRIG'), sonarPins.getFieldValue('ECHO')] : sonarDefaults();
    const sonarFns = [];
    if (usesSonar && !v2) {
      glob.push('// The distance sensor (HC-SR04)' + (sonarPins ? '' : ': add the "distance sensor" block to choose its pins') + '.',
        'const int SONAR_TRIG = ' + pinCode(trig) + ';', 'const int SONAR_ECHO = ' + pinCode(echo) + ';');
      sonarFns.push(['// The distance to the nearest obstacle in cm (400 when nothing answers): a 10 µs pulse on TRIG, then how\n' +
        '// long the echo takes to come back on ECHO, 58 µs for each centimetre there and back.\nfloat distanceCm()',
      'digitalWrite(SONAR_TRIG, LOW);\ndelayMicroseconds(2);\ndigitalWrite(SONAR_TRIG, HIGH);\ndelayMicroseconds(10);\n' +
        'digitalWrite(SONAR_TRIG, LOW);\nunsigned long us = pulseIn(SONAR_ECHO, HIGH, 25000);\nreturn us == 0 ? 400 : us / 58.0;\n']);
      if (has('rc_when_closer')) {
        glob.push('bool sonarWasClose = false;');
        sonarFns.push(['// True once each time something comes closer than cm, so a "when" script runs once.\nbool justCloserThan(float cm)',
          'bool now = distanceCm() < cm;\nbool rose = now && !sonarWasClose;\nsonarWasClose = now;\nreturn rose;\n']);
      }
    }
    if (usesLine) glob.push('LineSensor line;');
    if (usesImu) glob.push('IMU imu;');
    if (usesRobot) glob.push('RoboCoreDrive robot(motors, imu);');
    if (usesServos) glob.push('RoboCoreServos servos;');
    for (const e of edgeName.values()) glob.push('RoboCoreEdge ' + e + ';');
    for (const id of vars) {
      const t = types.get(id) || 'int', name = cpp.nameDB_.getName(id, Blockly.Names.NameType.VARIABLE);
      glob.push(t + ' ' + name + ' = ' + (t === 'String' ? '""' : '0') + ';');
    }
    if (l.length > 3) l.push('');
    if (glob.length) l.push(...glob, '');
    const lines = (code) => (code ? code.replace(/\n$/, '').split('\n') : []);
    for (const [sig, code] of sonarFns) l.push(sig + ' {', ...lines(code).map((x) => '  ' + x), '}', '');
    if (fns.length) {
      // Declared first, so they can call each other in any order.
      if (fns.length > 1) l.push(...fns.map(([sig]) => sig + ';'), '');
      for (const [sig, code] of fns) l.push(sig + ' {', ...lines(code), '}', '');
    }

    const setup = [];
    if (needSerial) setup.push('Serial.begin(115200);');
    if (has('rc_led')) setup.push('pinMode(LED_BUILTIN, OUTPUT);');
    for (const p of outPins) setup.push('pinMode(' + p + ', OUTPUT);');
    for (const p of inPins) if (!outPins.includes(p)) setup.push('pinMode(' + p + ', INPUT);');
    if (usesBtnPin) setup.push(v2 ? 'pinMode(USER_BUTTON, INPUT);' : 'pinMode(USER_BUTTON, INPUT_PULLUP);');
    if (usesMot) setup.push('motors.begin();');
    if (usesSonar && v2) setup.push('sonar.begin();');
    if (usesSonar && !v2) setup.push('pinMode(SONAR_TRIG, OUTPUT);', 'pinMode(SONAR_ECHO, INPUT);');
    if (usesLine) setup.push('line.begin();');
    // Last: it measures the gyro while the robot is still (0.3 s).
    if (imuBlocks) setup.push('imu.begin();');
    const setupBody = tops.filter((t) => t.type === 'rc_on_start').map(body).join('');
    const loopBody = whenCode.map((c) => ind(c) + '\n').join('') + tops.filter((t) => t.type === 'rc_forever').map(body).join('');
    l.push('void setup() {', ...setup.map((s) => '  ' + s), ...lines(setupBody), '}', '', 'void loop() {', ...lines(loopBody), '}', '');
    return l.join('\n');
  }

  // A "when …" hat's condition, checked on every pass of loop() (edge: its RoboCoreEdge for "when <condition>").
  function whenCond(t, edge) {
    switch (t.type) {
      case 'rc_when_user': return 'RoboCore::userJustPressed()';
      case 'rc_when_closer': return (CTX.board === 'v2' ? 'sonar.' : '') + 'justCloserThan(' + (cpp.valueToCode(t, 'CM', O.NONE) || '20') + ')';
      case 'rc_when_line': return t.getFieldValue('STATE') === 'lost' ? 'line.justLost()' : 'line.justFound()';
      case 'rc_when_tilt': return 'imu.' + ({ shaken: 'justShaken', flat: 'justFlat' }[t.getFieldValue('STATE')] || 'justTilted') + '()';
      case 'rc_when_timer': return 'RoboCore::timerPassed(' + (cpp.valueToCode(t, 'SECS', O.NONE) || '10') + ')';
      case 'rc_when': return (edge || 'when1') + '.rose(' + (cpp.valueToCode(t, 'COND', O.NONE) || 'false') + ')';
    }
    return null;
  }

  // A script top's C++ on its own (for Cog's "Explain this block").
  function rootCpp(t) {
    const b = t.type === 'procedures_defnoreturn' ? cpp.statementToCode(t, 'STACK') : cpp.statementToCode(t, 'DO');
    const head = { rc_on_start: 'void setup()', rc_forever: 'void loop()' }[t.type] ||
      (t.type === 'rc_when_receive' ? 'void ' + handler(t.getFieldValue('MSG')) + '()' : null) ||
      (t.type === 'procedures_defnoreturn' ? 'void ' + camel(t.getFieldValue('NAME')) + '()' : 'if (' + whenCond(t) + ')');
    return head + ' {\n' + b + '}';
  }

  let ws = null, onBlocksChange = null, onZoom = null, onSelect = null, onHistory = null, loading = false, timer = 0, lastScale = 0, lastSelection = '', lastHistory = '';
  const START_SCALE = 1;
  // The desktop apps' display size (Settings → Appearance; their WebViews are not scaled with the rest of the app, so
  // the page grows its own content: the blocks, the toolbox and the code). The web app's frames scale with the page.
  let ZOOM = 1;
  function setZoom(value) {
    const next = Number(value) > 0 ? Number(value) : 1;
    if (next === ZOOM) return;
    const before = ZOOM;
    ZOOM = next;
    document.documentElement.style.setProperty('--rc-zoom', String(ZOOM));
    if (ws) { ws.setScale(ws.scale * ZOOM / before); Blockly.svgResize(ws); }
  }

  // Relative to the display size, so 1 is still "the starting size".
  function reportZoom() {
    if (ws && onZoom && ws.scale !== lastScale) { lastScale = ws.scale; onZoom(ws.scale / ZOOM); }
  }

  // Whether Undo and Redo have anything to do, so the app can grey its buttons out (BK-09).
  function reportHistory() {
    if (!ws || !onHistory) return;
    const u = ws.getUndoStack().length > 0, r = ws.getRedoStack().length > 0;
    const k = `${u}${r}`;
    if (k !== lastHistory) { lastHistory = k; onHistory(u, r); }
  }

  // How a block reads (its own words, not the blocks inside it) and the C++ it makes, for Cog.
  function blockLabel(b) {
    return b.inputList.flatMap((i) => i.fieldRow.map((f) => f.getText())).filter((t) => t && t.trim()).join(' ').trim() || b.type;
  }
  function blockCpp(b) {
    cpp.init(ws);
    if (isRoot(b.type)) return rootCpp(b);
    const code = cpp.blockToCode(b, true);
    return (Array.isArray(code) ? code[0] : code).replace(/\n$/, '');
  }
  function reportSelection() {
    if (!ws || !onSelect) return;
    const b = Blockly.getSelected && Blockly.getSelected();
    const json = b && b.workspace === ws && !b.isShadow() ? JSON.stringify({ type: b.type, label: blockLabel(b), cpp: blockCpp(b) }) : '';
    if (json !== lastSelection) { lastSelection = json; onSelect(json); }
  }

  function zoomBy(dir) { if (ws) ws.zoomCenter(dir); }
  function resetZoom() { if (ws) { ws.setScale(START_SCALE * ZOOM); ws.scrollCenter(); } }

  // Blocks a student placed: not on start / forever, or the number fields inside other blocks.
  const countBlocks = (w) => w.getAllBlocks(false).filter((b) => !b.isShadow() && b.type !== 'rc_on_start' && b.type !== 'rc_forever').length;

  function sendBlocks() {
    timer = 0;
    if (!ws || !onBlocksChange) return;
    const json = JSON.stringify(Blockly.serialization.workspaces.save(ws));
    onBlocksChange(json, generate(ws), countBlocks(ws));
    reportSelection();
  }

  function emitBlocks() {
    clearTimeout(timer);
    timer = setTimeout(sendBlocks, 60);
  }

  // A Save or Verify pressed right after a change must not wait for the 60 ms pause.
  function flushBlocks() {
    if (timer) { clearTimeout(timer); sendBlocks(); }
  }

  function blocksOptions(o) {
    if (o.name != null) CTX.name = o.name;
    if (o.board) CTX.board = o.board;
    if (o.pins) CTX.pins = o.pins;
    if (o.tonePins) CTX.tonePins = o.tonePins;
    if (o.analogPins) CTX.analogPins = o.analogPins;
    if (o.userPin != null) CTX.userPin = o.userPin;
    if (o.led != null) CTX.led = o.led;
    if (o.zoom != null) setZoom(o.zoom);
  }

  function loadWorkspace(json, tidy) {
    loading = true;
    Blockly.Events.disable();
    try {
      ws.clear();
      if (json) {
        const data = JSON.parse(json);
        rememberMessages(data);
        Blockly.serialization.workspaces.load(data, ws);
      }
      if (tidy) ws.cleanUp();
    } catch (e) {
      console.error('RoboCore: could not load the blocks', e);
    } finally {
      Blockly.Events.enable();
      loading = false;
    }
    ws.clearUndo();
    ws.scrollCenter();
    emitBlocks();
  }

  const blocksApi = {
    async mount(optionsJson, json, tidy, onChange, onZoomChange, onSelectBlock, onHistoryChange) {
      await ready;
      const o = JSON.parse(optionsJson);
      blocksOptions(o);
      onBlocksChange = onChange;
      onZoom = onZoomChange;
      onSelect = onSelectBlock || null;
      onHistory = onHistoryChange || null;
      lastHistory = '';
      lastScale = 0;
      setTheme(o.theme);
      ws = Blockly.inject(document.getElementById('host'), {
        toolbox: TOOLBOX,
        renderer: 'robocore',
        theme: CTX.theme === 'navy' ? NAVY : PAPER_THEME,
        media: 'vendor/blockly/media/',
        grid: { spacing: 24, length: 1, colour: 'rgba(27,42,65,.4)', snap: true },
        // Ctrl/⌘ + wheel and trackpad pinch zoom; the plain wheel scrolls (move.wheel).
        zoom: { controls: true, wheel: true, pinch: true, startScale: START_SCALE * ZOOM, minScale: 0.4, maxScale: 3.75, scaleSpeed: 1.15 },
        move: { scrollbars: true, drag: true, wheel: true },
        trashcan: true,
        maxTrashcanContents: 32,
        sounds: false,
        plugins: { flyoutsVerticalToolbox: 'rcFlyout' },
      });
      registerMyBlocks(ws);
      drawControls(ws);
      // The app hides this frame while the C++ tab is open; re-measure when it shows again.
      new ResizeObserver(() => { if (ws) Blockly.svgResize(ws); }).observe(document.getElementById('host'));
      ws.addChangeListener(Blockly.Events.disableOrphans);
      ws.addChangeListener((e) => {
        if (e.type === Blockly.Events.VIEWPORT_CHANGE) reportZoom();
        if (e.type === Blockly.Events.SELECTED) reportSelection();
        // After Blockly has put the event on its undo stack.
        setTimeout(reportHistory, 0);
        if (loading || e.isUiEvent) return;
        emitBlocks();
      });
      // Ctrl/⌘ + = / − / 0 zoom the blocks (not the whole page).
      document.addEventListener('keydown', (e) => {
        if (!(e.ctrlKey || e.metaKey) || e.altKey) return;
        const dir = { '=': 1, '+': 1, '-': -1, '_': -1, '0': 0 }[e.key];
        if (dir === undefined) return;
        e.preventDefault();
        if (dir) zoomBy(dir); else resetZoom();
      });
      loadWorkspace(json, tidy);
      reportZoom();
      setTimeout(reportHistory, 0);
    },
    load(json, tidy) { if (ws) { loadWorkspace(json, tidy); setTimeout(reportHistory, 0); } },
    setOptions(optionsJson) {
      const o = JSON.parse(optionsJson);
      const nameOrBoard = (o.name != null && o.name !== CTX.name) || (o.board && o.board !== CTX.board);
      blocksOptions(o);
      if (o.theme && o.theme !== CTX.theme) { setTheme(o.theme); if (ws) ws.setTheme(CTX.theme === 'navy' ? NAVY : PAPER_THEME); }
      if (nameOrBoard) emitBlocks();
    },
    undo() { if (ws) ws.undo(false); },
    redo() { if (ws) ws.undo(true); },
    clear() { if (ws) { Blockly.Events.setGroup(true); ws.clear(); Blockly.Events.setGroup(false); } },
    count() { return ws ? countBlocks(ws) : 0; },
    zoom(dir) { zoomBy(dir); },
    zoomToFit() { if (ws) ws.zoomToFit(); },
    resetZoom() { resetZoom(); },
  };

  let PAPER_THEME = null, NAVY = null;
  function setTheme(t) {
    CTX.theme = t === 'navy' ? 'navy' : 'paper';
    document.documentElement.style.setProperty('--rc-bg', CTX.theme === 'navy' ? '#17253A' : PAPER);
    // Menus Blockly puts outside the workspace (dropdowns) follow the theme through this class.
    document.body.classList.toggle('rcNavy', CTX.theme === 'navy');
  }

  // ======================================================================= Code (Monaco)

  let editor = null, models = {}, onCodeChange = null, onCursor = null, onExplain = null, applying = false, words = [];

  function defineMonacoThemes() {
    const rules = (navy) => {
      const ink = navy ? 'F7F1E3' : '1B2A41', warm = navy ? 'E8B04B' : '8A5A00', soft = navy ? 'ACADAC' : '68717E';
      return [
        { token: '', foreground: ink },
        { token: 'keyword', foreground: ink, fontStyle: 'bold' },
        { token: 'type', foreground: ink, fontStyle: 'bold' },
        { token: 'number', foreground: warm },
        { token: 'string', foreground: warm },
        { token: 'comment', foreground: soft, fontStyle: 'italic' },
        { token: 'keyword.directive', foreground: ink, fontStyle: 'bold' },
        { token: 'delimiter', foreground: ink },
      ];
    };
    const common = {
      'editorSuggestWidget.background': '#FFFFFF', 'editorSuggestWidget.border': '#00000000',
      'editorSuggestWidget.selectedBackground': '#F2B01E38', 'editorHoverWidget.background': '#FFFFFF',
      'editorHoverWidget.border': '#00000000', 'diffEditor.insertedTextBackground': '#F2B01E38',
      'diffEditor.removedTextBackground': '#1B2A410F',
      'editor.lineHighlightBackground': '#F2B01E1F', 'editor.selectionBackground': '#F2B01E55',
      'editorOverviewRuler.errorForeground': '#1B2A41', 'editorOverviewRuler.warningForeground': '#8A5A00',
      'editorBracketMatch.border': '#F2B01E', 'editorBracketMatch.background': '#F2B01E33',
    };
    monaco.editor.defineTheme('robocore-paper', {
      base: 'vs', inherit: true, rules: rules(false),
      colors: Object.assign({}, common, {
        // Line numbers and the focus border at WCAG contrast (4.5:1 and 3:1).
        'editor.background': PAPER, 'editor.foreground': INK, 'editorLineNumber.foreground': '#6A7380', focusBorder: INK,
        'editorLineNumber.activeForeground': INK, 'editorError.foreground': INK, 'editorWarning.foreground': '#8A5A00',
        'editorCursor.foreground': INK,
      }),
    });
    monaco.editor.defineTheme('robocore-navy', {
      base: 'vs-dark', inherit: true, rules: rules(true),
      colors: Object.assign({}, common, {
        'editor.background': INK, 'editor.foreground': CREAM, 'editorLineNumber.foreground': '#8A93A0', focusBorder: YELLOW,
        'editorLineNumber.activeForeground': CREAM, 'editorError.foreground': CREAM, 'editorWarning.foreground': '#E8B04B',
        'editorCursor.foreground': CREAM, 'editorSuggestWidget.background': '#22344F', 'editorHoverWidget.background': '#22344F',
        'editorSuggestWidget.foreground': CREAM, 'editorHoverWidget.foreground': CREAM,
      }),
    });
  }

  // Suggestions, parameter hints and hovers from the app's Arduino + RoboCore list
  // ([name, '(params)', doc, reference url], lib/data/arduino_api.dart).
  const apiDoc = ([, , doc, url]) => (doc || '') + (url ? `\n\n[Arduino reference](${url})` : '');
  // The entry for a name as typed: exact, or by its last part (myMotors.drive → motors.drive).
  const apiFind = (name) => {
    const last = name.split(/::|\./).pop();
    return words.find(([w]) => w === name) || words.find(([w]) => w.endsWith('.' + last) || w.endsWith('::' + last)) || null;
  };

  function registerProviders() {
    monaco.languages.registerCompletionItemProvider('cpp', {
      triggerCharacters: ['.'],
      provideCompletionItems(model, pos) {
        const line = model.getLineContent(pos.lineNumber).slice(0, pos.column - 1);
        const m = /[A-Za-z_][\w.]*$/.exec(line);
        const typed = m ? m[0] : '';
        const range = new monaco.Range(pos.lineNumber, pos.column - typed.length, pos.lineNumber, pos.column);
        return {
          suggestions: words.map((e) => { const [w, params] = e; return {
            label: w,
            kind: params ? monaco.languages.CompletionItemKind.Function : monaco.languages.CompletionItemKind.Constant,
            detail: w + (params || ''),
            documentation: { value: apiDoc(e) },
            insertText: params ? w + '($0)' : w,
            insertTextRules: params ? monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet : undefined,
            range,
          }; }),
        };
      },
    });
    // Parameter hints (CD-05): the signature with the argument you are typing in bold.
    monaco.languages.registerSignatureHelpProvider('cpp', {
      signatureHelpTriggerCharacters: ['(', ','],
      signatureHelpRetriggerCharacters: [','],
      provideSignatureHelp(model, pos) {
        const text = model.getValueInRange({ startLineNumber: Math.max(1, pos.lineNumber - 5), startColumn: 1, endLineNumber: pos.lineNumber, endColumn: pos.column });
        let depth = 0, commas = 0, i = text.length - 1, quote = null;
        for (; i >= 0; i--) {
          const ch = text[i];
          if (quote) { if (ch === quote && text[i - 1] !== '\\') quote = null; continue; }
          if (ch === '"' || ch === "'") quote = ch;
          else if (ch === ')') depth++;
          else if (ch === '(') { if (depth === 0) break; depth--; }
          else if (ch === ',' && depth === 0) commas++;
          else if (ch === ';' || ch === '{' || ch === '}') return null;
        }
        if (i < 0) return null;
        const m = /([A-Za-z_][\w.:]*)\s*$/.exec(text.slice(0, i));
        const hit = m && apiFind(m[1]);
        if (!hit || !hit[1]) return null;
        const params = hit[1].replace(/^\(|\)$/g, '').split(',').map((x) => x.trim()).filter(Boolean);
        // Offsets, so “pin” in pinMode(pin, mode) marks the argument, not the start of the name.
        let at = hit[0].length + 1;
        const parts = params.map((x) => { const r = [at, at + x.length]; at += x.length + 2; return { label: r }; });
        return {
          value: {
            signatures: [{ label: hit[0] + '(' + params.join(', ') + ')', documentation: { value: apiDoc(hit) }, parameters: parts }],
            activeSignature: 0,
            activeParameter: Math.min(commas, Math.max(0, params.length - 1)),
          },
          dispose() {},
        };
      },
    });
    monaco.languages.registerHoverProvider('cpp', {
      provideHover(model, pos) {
        const line = model.getLineContent(pos.lineNumber);
        const re = /[A-Za-z_][\w.:]*/g;
        let m;
        while ((m = re.exec(line))) {
          if (pos.column - 1 >= m.index && pos.column - 1 <= m.index + m[0].length) {
            const hit = apiFind(m[0]);
            if (!hit) return null;
            // Signature, a short doc and the Arduino reference link (CD-06).
            return {
              range: new monaco.Range(pos.lineNumber, m.index + 1, pos.lineNumber, m.index + m[0].length + 1),
              contents: [{ value: '```cpp\n' + hit[0] + (hit[1] || '') + '\n```' }, { value: apiDoc(hit) }],
            };
          }
        }
        return null;
      },
    });
  }

  // “Change spelling to 'digitalWrite'”: from gcc's “did you mean …”, or a known name that differs only in case.
  function spellingFix(model, m) {
    const word = model.getWordAtPosition({ lineNumber: m.startLineNumber, column: m.startColumn });
    if (!word) return null;
    let to = (/did you mean '([\w:.]+)'/.exec(m.message) || [])[1];
    if (to) to = to.split(/::|\./).pop();
    if (!to) {
      const lower = word.word.toLowerCase();
      const hit = words.find(([w]) => w.split(/::|\./).pop().toLowerCase() === lower);
      if (hit) to = hit[0].split(/::|\./).pop();
    }
    if (!to || to === word.word) return null;
    return {
      title: `Change spelling to '${to}'`, kind: 'quickfix', diagnostics: [m], isPreferred: true,
      edit: { edits: [{ resource: model.uri, versionId: model.getVersionId(), textEdit: {
        range: new monaco.Range(m.startLineNumber, word.startColumn, m.startLineNumber, word.endColumn), text: to } }] },
    };
  }

  let codeFont = 13;
  function codeOptions(o) {
    const opts = {};
    if (o.fontSize) codeFont = o.fontSize;
    if (o.zoom != null) setZoom(o.zoom);
    if (o.fontSize || o.zoom != null) {
      opts.fontSize = codeFont * ZOOM;
      opts.lineHeight = Math.round(20 * ZOOM);
    }
    if (o.wrap != null) opts.wordWrap = o.wrap ? 'on' : 'off';
    if (o.autocomplete != null) opts.quickSuggestions = o.autocomplete;
    if (o.words) words = o.words;
    if (o.theme) { setTheme(o.theme); monaco.editor.setTheme(CTX.theme === 'navy' ? 'robocore-navy' : 'robocore-paper'); }
    return opts;
  }

  const codeApi = {
    async mount(optionsJson, onChange, onCursorMove, onExplainLine) {
      await ready;
      onCodeChange = onChange;
      onCursor = onCursorMove;
      onExplain = onExplainLine || null;
      const o = JSON.parse(optionsJson);
      const opts = codeOptions(o);
      // Monaco measures one character and places the cursor by multiplying it. Measured before JetBrains Mono had
      // loaded, that was another font's width, and the cursor drifted away from the text along a line (several
      // characters in the Mac app's WebKit). So the font comes first, Monaco measures again whenever fonts load, and
      // the cursor is placed by measuring the text itself (disableMonospaceOptimizations).
      try {
        await Promise.all(['400', '700'].map((w) => document.fonts.load(`${w} 13px 'JetBrains Mono'`)));
      } catch (_) { /* a font that can't load: the fallback, measured as it is */ }
      editor = monaco.editor.create(document.getElementById('host'), Object.assign({
        language: 'cpp',
        disableMonospaceOptimizations: true,
        theme: CTX.theme === 'navy' ? 'robocore-navy' : 'robocore-paper',
        automaticLayout: true,
        minimap: { enabled: false },
        fontFamily: "'JetBrains Mono', ui-monospace, monospace",
        fontSize: 13,
        lineHeight: 20,
        tabSize: 2,
        insertSpaces: true,
        glyphMargin: true,
        folding: true,
        showFoldingControls: 'mouseover',
        stickyScroll: { enabled: false },
        parameterHints: { enabled: true },
        lightbulb: { enabled: 'on' },
        renderLineHighlight: 'all',
        bracketPairColorization: { enabled: false },
        // A touchpad pinch must not change the code's size: that is Settings → Font size (see the wheel listener below).
        mouseWheelZoom: false,
        guides: { bracketPairs: false, indentation: true },
        scrollBeyondLastLine: false,
        fixedOverflowWidgets: true,
        padding: { top: 8 },
      }, opts));
      document.fonts.addEventListener('loadingdone', () => monaco.editor.remeasureFonts());
      document.fonts.ready.then(() => monaco.editor.remeasureFonts());
      editor.onDidChangeModelContent(() => {
        if (applying || !onCodeChange) return;
        const model = editor.getModel();
        const key = Object.keys(models).find((k) => models[k] === model);
        onCodeChange(key || '', model.getValue());
      });
      editor.onDidChangeCursorPosition((e) => {
        if (onCursor) onCursor(e.position.lineNumber, e.position.column);
      });
      // Quick fixes on compile problems (lightbulb, Ctrl+. or the hover): the compiler's spelling suggestion
      // (CD-08), and Explain with Cog.
      const explain = onExplain ? editor.addCommand(0, (_, line) => onExplain(line)) : null;
      monaco.languages.registerCodeActionProvider('cpp', {
        provideCodeActions(model, range, context) {
          const marks = context.markers.filter((m) => m.owner === 'arduino-cli').slice(0, 1);
          const actions = [];
          for (const m of marks) {
            const fix = spellingFix(model, m);
            if (fix) actions.push(fix);
            if (explain) {
              actions.push({
                title: 'Explain with Cog', kind: 'quickfix', diagnostics: [m], isPreferred: false,
                command: { id: explain, title: 'Explain with Cog', arguments: [m.startLineNumber] },
              });
            }
          }
          return { actions, dispose() {} };
        },
      });
      if (onExplain) {
        editor.addAction({
          id: 'robocore.explainWithCog', label: 'Explain with Cog', contextMenuGroupId: '1_cog', contextMenuOrder: 0,
          run: (ed) => onExplain(ed.getPosition().lineNumber),
        });
      }
    },
    // Shows file `key` with `text`. Text that differs from the editor's (blocks regenerated it,
    // or another file was opened) replaces the model's content.
    setFile(key, text, readOnly) {
      if (!editor) return;
      let model = models[key];
      if (!model) {
        model = monaco.editor.createModel(text, 'cpp', monaco.Uri.parse('file:///' + encodeURI(key)));
        models[key] = model;
      } else if (model.getValue() !== text) {
        applying = true;
        model.pushEditOperations([], [{ range: model.getFullModelRange(), text }], () => null);
        applying = false;
      }
      if (editor.getModel() !== model) editor.setModel(model);
      editor.updateOptions({ readOnly: !!readOnly, domReadOnly: !!readOnly });
    },
    setOptions(optionsJson) { if (editor) editor.updateOptions(codeOptions(JSON.parse(optionsJson))); },
    // problems: [{line, column, message, severity}] for the file on screen.
    setMarkers(key, problemsJson) {
      const model = models[key];
      if (!model) return;
      const sev = { error: monaco.MarkerSeverity.Error, warning: monaco.MarkerSeverity.Warning };
      const markers = JSON.parse(problemsJson).filter((p) => p.line >= 1 && p.line <= model.getLineCount()).map((p) => {
        const col = Math.max(1, p.column || 1);
        const word = p.column ? model.getWordAtPosition({ lineNumber: p.line, column: col }) : null;
        return {
          severity: sev[p.severity] || monaco.MarkerSeverity.Info,
          message: p.message,
          startLineNumber: p.line,
          startColumn: word ? word.startColumn : (p.column ? col : model.getLineFirstNonWhitespaceColumn(p.line) || 1),
          endLineNumber: p.line,
          endColumn: word ? word.endColumn : model.getLineMaxColumn(p.line),
        };
      });
      monaco.editor.setModelMarkers(model, 'arduino-cli', markers);
    },
    reveal(line, column) {
      if (!editor) return;
      editor.revealLineInCenter(line);
      editor.setPosition({ lineNumber: line, column: Math.max(1, column || 1) });
      editor.focus();
    },
    find() { if (editor) { editor.focus(); editor.getAction('actions.find').run(); } },
    // A Monaco command by id (undo, redo, editor.action.commentLine …), for the macOS app's menu bar.
    action(id) { if (editor) { editor.focus(); editor.trigger('menu', id, null); } },
    focus() { if (editor) editor.focus(); },
  };

  // ======================================================================= start-up

  const ready = (async () => {
    if (MODE === 'blocks') {
      await loadScript('vendor/blockly/blockly_compressed.js');
      await loadScript('vendor/blockly/blocks_compressed.js');
      await loadScript('vendor/blockly/msg/en.js');
      defineBlocks();
      registerRenderer();
      registerFlyout();
      PAPER_THEME = theme(false);
      NAVY = theme(true);
      cpp = makeGenerator();
    } else {
      await loadScript('vendor/monaco/vs/loader.js');
      await new Promise((resolve, reject) => {
        window.require.config({ paths: { vs: 'vendor/monaco/vs' } });
        window.require(['vs/editor/editor.main'], resolve, reject);
      });
      defineMonacoThemes();
      registerProviders();
    }
  })();

  // ======================================================================= The IDE's shortcuts

  // Ctrl/⌘ + S, R, U, I, B and J are the IDE's (Save, Verify, Upload, Ask Cog, sidebar, console), also while typing here. Taken
  // before Blockly, Monaco or the browser see them: otherwise the browser would save the page (S), reload
  // it (R) or show its source (U), and Monaco would open suggestions (I). The app sets the handler.
  const IDE_KEYS = { s: 'save', r: 'verify', u: 'upload', i: 'cog', b: 'sidebar', j: 'console' };
  let onIdeKey = null;
  window.addEventListener('keydown', (e) => {
    if (!(e.ctrlKey || e.metaKey) || e.altKey || e.shiftKey) return;
    const k = /^[a-z]$/i.test(e.key) ? e.key.toLowerCase() : /^Key[A-Z]$/.test(e.code) ? e.code.slice(3).toLowerCase() : '';
    const action = IDE_KEYS[k];
    if (!action) return;
    e.preventDefault();
    e.stopPropagation();
    if (e.repeat || !onIdeKey) return;
    if (MODE === 'blocks') flushBlocks();
    onIdeKey(action);
  }, true);

  // A touchpad pinch arrives as Ctrl + wheel. In the code editor it does nothing (the font size is in Settings); without
  // this Monaco would scroll on it and Chrome would zoom the whole page. In the blocks, Blockly zooms the workspace.
  if (MODE === 'code') {
    window.addEventListener('wheel', (e) => {
      if (!e.ctrlKey && !e.metaKey) return;
      e.preventDefault();
      e.stopPropagation();
    }, { capture: true, passive: false });
  }

  window.rcEditor = {
    mode: MODE,
    ready,
    blocks: blocksApi,
    code: codeApi,
    setIdeKeys(handler) { onIdeKey = handler || null; },
    // For checks: the toolbox (every block a student can take), and the C++ for a saved workspace.
    toolbox: TOOLBOX,
    generateFor(json, optionsJson) {
      blocksOptions(JSON.parse(optionsJson || '{}'));
      const headless = new Blockly.Workspace();
      const data = JSON.parse(json);
      rememberMessages(data);
      Blockly.serialization.workspaces.load(data, headless);
      headless.getAllBlocks(false).forEach((b) => {
        const root = b.getRootBlock();
        if (!isRoot(root.type) && b.setDisabledReason) b.setDisabledReason(true, 'ORPHANED_BLOCK');
      });
      const code = generate(headless);
      headless.dispose();
      return code;
    },
  };

  // ======================================================================= The desktop app

  // The macOS app shows this page in a WebView (lib/ui/editor/web_editors_native.dart), which cannot hand the page
  // Dart functions the way the web app does through the iframe. It calls rcNative and the other rcEditor methods
  // with runJavaScript, and the page answers on the RoboCoreHost channel with JSON arrays: [event, ...args].
  if (window.RoboCoreHost) {
    const send = (...m) => window.RoboCoreHost.postMessage(JSON.stringify(m));
    const failed = (e) => send('error', String(e && e.stack || e));
    window.rcEditor.setIdeKeys((action) => send('key', action));
    window.rcNative = {
      mountBlocks(optionsJson, json, tidy) {
        blocksApi.mount(optionsJson, json, tidy,
          (j, code, count) => send('change', j, code, count),
          (scale) => send('zoom', scale),
          (j) => send('select', j),
          (canUndo, canRedo) => send('history', canUndo, canRedo)).then(() => send('mounted'), failed);
      },
      mountCode(optionsJson, explain) {
        codeApi.mount(optionsJson,
          (key, text) => send('change', key, text),
          (line, column) => send('cursor', line, column),
          explain ? (line) => send('explain', line) : null).then(() => send('mounted'), failed);
      },
    };
    window.addEventListener('error', (e) => failed(e.error || e.message));
    send('loaded');
  }
})();
