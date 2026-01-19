# Support Bundle Analysis Skill

## Overview

This skill provides systematic guidance for analyzing Longhorn support bundles to diagnose issues in Kubernetes clusters.

## Skill Structure (New Architecture)

As of 2026-01-16, this skill has been restructured into three focused modules:

### Module Files

```
.opencode/skill/support-bundle-analysis/
  SKILL.md               (Entrypoint, ~150 lines)
  diagnostic-flows.md    (Technical Module, ~400 lines)
  patterns-library.md    (Knowledge Base, ~350 lines)
  extract-bundle.sh      (Bundle extraction utility)
  README.md              (This file)
```

### Module Responsibilities

| Module | Purpose | When to Read |
|--------|---------|--------------|
| **SKILL.md** | Entry point with Pre-Analysis Requirements, Phase 0-1, and navigation | Always start here |
| **diagnostic-flows.md** | Phase 2-3 deep diagnosis procedures (Pod/Node/Storage/Network) | When performing deep diagnosis |
| **patterns-library.md** | Phase 4 root cause analysis, error patterns, real-world examples | When analyzing root causes |

## Usage Workflow

```
1. Extract support bundle using extract-bundle.sh
2. Start with SKILL.md (Pre-Analysis Requirements are MANDATORY)
3. Follow Decision Tree in SKILL.md to navigate to appropriate modules
4. Use diagnostic-flows.md for Phase 2-3 (deep diagnosis)
5. Use patterns-library.md for Phase 4 (root cause analysis)
```

## Quick Links

- **Start analysis**: Read `SKILL.md` first
- **Need diagnostic procedures**: See `diagnostic-flows.md`
- **Need error patterns or examples**: See `patterns-library.md`

## Related Documentation

- Rancher support bundle kit: https://github.com/rancher/support-bundle-kit

---

**Last Updated**: 2026-01-16  
**Architecture Version**: 2.0 (Modular)
