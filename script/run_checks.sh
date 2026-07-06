#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CHECK_BINARY="$ROOT_DIR/.build/rivalradar-checks"

swiftc \
  Sources/RivalRadar/Models/Competitor.swift \
  Sources/RivalRadar/Models/SourceModels.swift \
  Sources/RivalRadar/Models/IntelligenceItem.swift \
  Sources/RivalRadar/Models/RunLog.swift \
  Sources/RivalRadar/Models/TavilyBulkConfiguration.swift \
  Sources/RivalRadar/Models/TavilyRecommendationPrompt.swift \
  Sources/RivalRadar/Models/TavilySourceJSONConfig.swift \
  Sources/RivalRadar/Models/SourceRecommendationConfiguration.swift \
  Sources/RivalRadar/Support/StringUtilities.swift \
  Sources/RivalRadar/Support/Hashing.swift \
  Sources/RivalRadar/Support/TimeFilterPreset.swift \
  Sources/RivalRadar/Services/URLNormalizer.swift \
  Sources/RivalRadar/Services/DedupeService.swift \
  Sources/RivalRadar/Services/HTMLExtractor.swift \
  Sources/RivalRadar/Services/RSSFeedParser.swift \
  Sources/RivalRadar/Services/ChromeSessionReader.swift \
  Sources/RivalRadar/Services/SourceCollector.swift \
  Sources/RivalRadar/Services/OpenAIChatClient.swift \
  Sources/RivalRadar/Services/IntelligenceAnalyzer.swift \
  Sources/RivalRadar/Services/TavilyConfigurationAdvisor.swift \
  Sources/RivalRadar/Services/SourceRecommendationAdvisor.swift \
  Sources/RivalRadar/Services/ReportGenerator.swift \
  Sources/RivalRadar/Stores/SQLiteDatabase.swift \
  Checks/RivalRadarChecks.swift \
  -lsqlite3 \
  -framework Security \
  -o "$CHECK_BINARY"

"$CHECK_BINARY"
