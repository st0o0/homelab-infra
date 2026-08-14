import { readFileSync, writeFileSync, readdirSync } from "fs";
import { join } from "path";

const dir = join(
  import.meta.dirname,
  "..",
  "stacks/metrics/grafana/provisioning/dashboards/json"
);

const DASHBOARD_KEY_ORDER = [
  "uid",
  "title",
  "description",
  "tags",
  "editable",
  "graphTooltip",
  "refresh",
  "time",
  "timezone",
  "timepicker",
  "schemaVersion",
  "annotations",
  "templating",
  "panels",
];

const PANEL_KEY_ORDER = [
  "type",
  "title",
  "description",
  "gridPos",
  "datasource",
  "fieldConfig",
  "options",
  "transformations",
  "targets",
  "repeat",
  "repeatDirection",
  "maxPerRow",
  "collapsed",
  "panels",
];

const TARGET_KEY_ORDER = ["refId", "datasource", "expr", "legendFormat"];

const FIELDCONFIG_DEFAULTS_KEY_ORDER = [
  "color",
  "custom",
  "decimals",
  "displayName",
  "links",
  "mappings",
  "max",
  "min",
  "noValue",
  "thresholds",
  "unit",
];

const INLINE_THRESHOLD = 90;

function sortKeys(obj, order) {
  const sorted = {};
  for (const key of order) {
    if (key in obj) sorted[key] = obj[key];
  }
  for (const key of Object.keys(obj)) {
    if (!(key in sorted)) sorted[key] = obj[key];
  }
  return sorted;
}

function isDefaultThreshold(thresholds) {
  if (!thresholds) return false;
  const steps = thresholds.steps;
  return (
    thresholds.mode === "absolute" &&
    Array.isArray(steps) &&
    steps.length === 1 &&
    steps[0].color === "green" &&
    steps[0].value === null
  );
}

function compactStringify(val) {
  if (val === null) return "null";
  if (typeof val !== "object") return JSON.stringify(val);
  if (Array.isArray(val)) {
    return "[" + val.map(compactStringify).join(", ") + "]";
  }
  const pairs = Object.entries(val).map(
    ([k, v]) => JSON.stringify(k) + ": " + compactStringify(v)
  );
  return "{" + pairs.join(", ") + "}";
}

function isSimpleValue(val) {
  return val === null || typeof val !== "object";
}

function isShallowObj(val) {
  if (val === null || typeof val !== "object") return true;
  if (Array.isArray(val)) return val.every(isSimpleValue);
  return Object.values(val).every(isSimpleValue);
}

function stringify(value, indent) {
  if (value === null) return "null";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") return String(value);
  if (typeof value === "string") return JSON.stringify(value);

  const pad = " ".repeat(indent);
  const padInner = " ".repeat(indent + 2);

  if (Array.isArray(value)) {
    if (value.length === 0) return "[]";

    const compact = compactStringify(value);
    if (compact.length <= INLINE_THRESHOLD && isShallowObj(value[0])) {
      if (value.every(isSimpleValue)) return compact;
      if (value.every(isShallowObj)) {
        if (compact.length + indent <= 120) return compact;
      }
    }

    const items = value.map((v) => padInner + stringify(v, indent + 2));
    return `[\n${items.join(",\n")}\n${pad}]`;
  }

  if (typeof value === "object") {
    const keys = Object.keys(value);
    if (keys.length === 0) return "{}";

    const compact = compactStringify(value);
    if (compact.length <= INLINE_THRESHOLD && isShallowObj(value)) {
      return compact;
    }

    const entries = keys.map(
      (k) => `${padInner}${JSON.stringify(k)}: ${stringify(value[k], indent + 2)}`
    );
    return `{\n${entries.join(",\n")}\n${pad}}`;
  }

  return JSON.stringify(value);
}

function cleanTarget(target, panelDs) {
  const cleaned = { ...target };

  if (
    panelDs &&
    cleaned.datasource &&
    JSON.stringify(cleaned.datasource) === JSON.stringify(panelDs)
  ) {
    delete cleaned.datasource;
  }

  delete cleaned.editorMode;
  delete cleaned.exemplar;
  if (cleaned.instant === false) delete cleaned.instant;
  if (cleaned.range === true) delete cleaned.range;
  if (cleaned.interval === "") delete cleaned.interval;
  if (cleaned.intervalFactor === 1) delete cleaned.intervalFactor;
  if (cleaned.format === "time_series") delete cleaned.format;
  if (cleaned.resultFormat === "time_series") delete cleaned.resultFormat;
  if (cleaned.step === undefined || cleaned.step === "") delete cleaned.step;

  if (cleaned.legendFormat === "") delete cleaned.legendFormat;
  if (cleaned.queryType === "range") delete cleaned.queryType;

  return sortKeys(cleaned, TARGET_KEY_ORDER);
}

function cleanPanel(panel) {
  if (panel.type === "row") {
    const cleaned = { ...panel };
    delete cleaned.id;
    if (Array.isArray(cleaned.panels) && cleaned.panels.length === 0) {
      delete cleaned.panels;
    }
    if (cleaned.collapsed === false) delete cleaned.collapsed;
    return sortKeys(cleaned, PANEL_KEY_ORDER);
  }

  const cleaned = { ...panel };

  delete cleaned.id;

  if (cleaned.fieldConfig) {
    cleaned.fieldConfig = { ...cleaned.fieldConfig };
    if (cleaned.fieldConfig.defaults) {
      cleaned.fieldConfig.defaults = { ...cleaned.fieldConfig.defaults };

      if (
        Array.isArray(cleaned.fieldConfig.defaults.mappings) &&
        cleaned.fieldConfig.defaults.mappings.length === 0
      ) {
        delete cleaned.fieldConfig.defaults.mappings;
      }

      if (isDefaultThreshold(cleaned.fieldConfig.defaults.thresholds)) {
        delete cleaned.fieldConfig.defaults.thresholds;
      }

      cleaned.fieldConfig.defaults = sortKeys(
        cleaned.fieldConfig.defaults,
        FIELDCONFIG_DEFAULTS_KEY_ORDER
      );
    }

    if (
      Array.isArray(cleaned.fieldConfig.overrides) &&
      cleaned.fieldConfig.overrides.length === 0
    ) {
      delete cleaned.fieldConfig.overrides;
    }
  }

  if (
    Array.isArray(cleaned.transformations) &&
    cleaned.transformations.length === 0
  ) {
    delete cleaned.transformations;
  }

  if (Array.isArray(cleaned.links) && cleaned.links.length === 0) {
    delete cleaned.links;
  }

  const panelDs = cleaned.datasource;
  if (Array.isArray(cleaned.targets)) {
    cleaned.targets = cleaned.targets.map((t) => cleanTarget(t, panelDs));
  }

  return sortKeys(cleaned, PANEL_KEY_ORDER);
}

function cleanDashboard(dashboard) {
  const cleaned = { ...dashboard };

  delete cleaned.id;
  delete cleaned.__elements;
  delete cleaned.liveNow;
  delete cleaned.version;
  delete cleaned.gnetId;
  delete cleaned.style;
  if (cleaned.fiscalYearStartMonth === 0) delete cleaned.fiscalYearStartMonth;
  if (cleaned.weekStart === "" || cleaned.weekStart === undefined)
    delete cleaned.weekStart;
  if (cleaned.weekStyle === "" || cleaned.weekStyle === undefined)
    delete cleaned.weekStyle;

  if (Array.isArray(cleaned.links) && cleaned.links.length === 0) {
    delete cleaned.links;
  }

  if (Array.isArray(cleaned.panels)) {
    cleaned.panels = cleaned.panels.map(cleanPanel);
  }

  return sortKeys(cleaned, DASHBOARD_KEY_ORDER);
}

const files = readdirSync(dir).filter((f) => f.endsWith(".json"));
let totalBefore = 0;
let totalAfter = 0;

for (const file of files) {
  const path = join(dir, file);
  const raw = readFileSync(path, "utf8");
  const dashboard = JSON.parse(raw);
  const cleaned = cleanDashboard(dashboard);
  const output = stringify(cleaned, 0) + "\n";

  totalBefore += raw.length;
  totalAfter += output.length;

  const saved = raw.length - output.length;
  const pct = ((saved / raw.length) * 100).toFixed(1);
  console.log(
    `${file.padEnd(25)} ${raw.length.toString().padStart(7)} -> ${output.length.toString().padStart(7)}  (${saved > 0 ? "-" : "+"}${Math.abs(saved)} bytes, ${pct}%)`
  );

  writeFileSync(path, output);
}

const totalSaved = totalBefore - totalAfter;
const totalPct = ((totalSaved / totalBefore) * 100).toFixed(1);
console.log(
  `\nTotal: ${totalBefore} -> ${totalAfter}  (-${totalSaved} bytes, ${totalPct}%)`
);
