import Foundation

/// Converts icon positions between different display configurations.
/// Port of the shell script's `remap_coordinates()` and `find_display_for_point()`.
enum CoordinateConverter {
    /// Finds which display contains the given point.
    /// Falls back to the first display if no display contains the point.
    static func findDisplay(forPoint px: Int, _ py: Int, in displays: [DisplayFrame]) -> DisplayFrame {
        for display in displays where display.contains(px: px, py: py) {
            return display
        }
        return displays[0]
    }

    /// Finds the index of the display containing the given point.
    /// Falls back to 0 if no display contains the point.
    static func findDisplayIndex(forPoint px: Int, _ py: Int, in displays: [DisplayFrame]) -> Int {
        for (i, display) in displays.enumerated() where display.contains(px: px, py: py) {
            return i
        }
        return 0
    }

    /// Match saved displays to current displays by geometry.
    ///
    /// Returns a mapping of savedIndex → currentIndex.
    /// Matching priority: overlap area (higher = better), then center distance (lower = better).
    /// Enforces unique assignment when possible (|saved| ≤ |current|).
    /// When |saved| > |current|, multiple saved displays may map to the same current display.
    /// Unmatched saved displays fall back to primary (index 0).
    static func matchDisplays(
        saved: [DisplayFrame],
        current: [DisplayFrame]
    ) -> [Int: Int] {
        guard !saved.isEmpty, !current.isEmpty else { return [:] }

        // Step 1: Build score matrix — (overlap, negDistance) per saved×current pair.
        // Higher overlap is better; for equal overlap, smaller distance is better.
        var scores: [[(overlap: Int, negDist: Int)]] = []
        for savedFrame in saved {
            var row: [(overlap: Int, negDist: Int)] = []
            for currentFrame in current {
                let overlap = savedFrame.overlapArea(with: currentFrame)
                let dx = savedFrame.center.x - currentFrame.center.x
                let dy = savedFrame.center.y - currentFrame.center.y
                let dist = dx * dx + dy * dy
                row.append((overlap: overlap, negDist: -dist))
            }
            scores.append(row)
        }

        // Step 2: Greedy assignment with uniqueness.
        // Sort saved indices by their best score (descending) so the strongest
        // matches claim current displays first.
        let sortedSaved = saved.indices.sorted { a, b in
            let bestA = scores[a].max { lhs, rhs in (lhs.overlap, lhs.negDist) < (rhs.overlap, rhs.negDist) }!
            let bestB = scores[b].max { lhs, rhs in (lhs.overlap, lhs.negDist) < (rhs.overlap, rhs.negDist) }!
            return (bestA.overlap, bestA.negDist) > (bestB.overlap, bestB.negDist)
        }

        var mapping: [Int: Int] = [:]
        var claimed: Set<Int> = []

        for si in sortedSaved {
            // Pick best unclaimed current display
            var bestIndex = -1
            var bestScore: (overlap: Int, negDist: Int) = (0, Int.min)

            for ci in current.indices where !claimed.contains(ci) {
                let s = scores[si][ci]
                if (s.overlap, s.negDist) > (bestScore.overlap, bestScore.negDist) {
                    bestScore = s
                    bestIndex = ci
                }
            }

            if bestIndex >= 0 {
                mapping[si] = bestIndex
                claimed.insert(bestIndex)
            } else {
                // All current displays claimed (|saved| > |current|) — allow sharing.
                // Pick overall best current display for this saved display.
                var fallbackIndex = 0
                var fallbackScore: (overlap: Int, negDist: Int) = (scores[si][0].overlap, scores[si][0].negDist)
                for ci in 1 ..< current.count {
                    let s = scores[si][ci]
                    if (s.overlap, s.negDist) > (fallbackScore.overlap, fallbackScore.negDist) {
                        fallbackScore = s
                        fallbackIndex = ci
                    }
                }
                mapping[si] = fallbackIndex
            }
        }

        return mapping
    }

    /// Remap icon positions from saved display layout to current display layout.
    ///
    /// Algorithm:
    /// 1. Match saved displays to current displays by geometry overlap/proximity
    /// 2. Icons on matched displays: remap relative position to matched current display
    /// 3. Icons displaced (source display mapped to a different display): park at bottom
    ///    of the target display in a grid, leaving existing icons untouched
    /// 4. Clamp all positions with 20px padding
    static func remap(
        icons: [IconPosition],
        from savedDisplays: [DisplayFrame],
        to currentDisplays: [DisplayFrame]
    ) -> [IconPosition] {
        guard !currentDisplays.isEmpty, !savedDisplays.isEmpty else {
            return icons
        }

        // If layouts are identical, return as-is
        if savedDisplays == currentDisplays {
            return icons
        }

        let pad = 20
        let mapping = matchDisplays(saved: savedDisplays, current: currentDisplays)

        // Determine which saved displays are "native" matches (mapped to a current display
        // that overlaps them) vs "displaced" (mapped to a non-overlapping display).
        var nativeMapping: Set<Int> = [] // saved indices with overlap
        for (si, savedFrame) in savedDisplays.enumerated() {
            guard let ci = mapping[si] else { continue }
            if savedFrame.overlapArea(with: currentDisplays[ci]) > 0 {
                nativeMapping.insert(si)
            }
        }

        // Separate icons into native (remap normally) and displaced (park at bottom)
        var result: [IconPosition] = []
        // displaced icons grouped by target current display index
        var displacedByTarget: [Int: [IconPosition]] = [:]

        for icon in icons {
            let savedIdx = findDisplayIndex(forPoint: icon.x, icon.y, in: savedDisplays)
            let targetIdx = mapping[savedIdx] ?? 0
            let target = currentDisplays[targetIdx]

            if nativeMapping.contains(savedIdx) {
                // Native: remap relative position to matched display
                let orig = savedDisplays[savedIdx]
                let relX = icon.x - orig.x
                let relY = icon.y - orig.y

                var newX = target.x + relX
                var newY = target.y + relY

                newX = max(target.x + pad, min(newX, target.x + target.width - pad))
                newY = max(target.y + pad, min(newY, target.y + target.height - pad))

                result.append(IconPosition(name: icon.name, x: newX, y: newY))
            } else {
                // Displaced: queue for parking at bottom of target display
                displacedByTarget[targetIdx, default: []].append(icon)
            }
        }

        // Park displaced icons at the bottom of their target display in a grid
        let gridSpacing = 100 // spacing between parked icons

        for (targetIdx, displaced) in displacedByTarget {
            let target = currentDisplays[targetIdx]
            let cols = max(1, (target.width - 2 * pad) / gridSpacing)

            for (i, icon) in displaced.enumerated() {
                let col = i % cols
                let row = i / cols

                // Start from bottom-right, fill leftward and upward
                let newX = target.x + target.width - pad - (col + 1) * gridSpacing + gridSpacing / 2
                let newY = target.y + target.height - pad - (row + 1) * gridSpacing + gridSpacing / 2

                // Clamp within bounds
                let clampedX = max(target.x + pad, min(newX, target.x + target.width - pad))
                let clampedY = max(target.y + pad, min(newY, target.y + target.height - pad))

                result.append(IconPosition(name: icon.name, x: clampedX, y: clampedY))
            }
        }

        return result
    }
}
