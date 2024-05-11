import Foundation


/// GrowthBook Utils Class
///
/// Contains Methods for:
/// - hash
/// - inNameSpace
/// - getEqualWeights
/// - getBucketRanges
/// - chooseVariation
/// - getGBNameSpace
public class Utils {
    
    /// Hashes a string to a float between 0 and 1
    static func hash(seed: String, value: String, version: Float) -> Float? {
        
        switch version {
        case 2:
            // New unbiased hashing algorithm
            let combinedValue = seed + value
            let hashedCombinedValue = digest(combinedValue).description + ""
            let hashedValue = digest(hashedCombinedValue) % 10000
            return Float(hashedValue) / 10000
        case 1:
            // Original biased hashing algorithm (keep for backwards compatibility)
            let combinedValue = value + seed
            let hashedValue = digest(combinedValue)
            return Float(hashedValue % 1000) / 1000
        default:
            // Unknown hash version
            return nil
        }
    }
    
    ///This is a helper method to evaluate `filters` for both feature flags and experiments.
    static func isFilteredOut(filters: [Filter], context: Context, attributeOverrides: JSON) -> Bool {
        return filters.contains { filter in
            let hashAttribute = Utils.getHashAttribute(context: context, attr: filter.attribute, attributeOverrides: attributeOverrides)
            let hashValue = hashAttribute.hashValue
            
            let hash = hash(seed: filter.seed, value: hashValue, version: filter.hashVersion)
            guard let hashValue = hash else { return true }
            
            return !filter.ranges.contains { range in
                return inRange(n: hashValue, range: range)
            }
        }
    }

    /// This checks if a userId is within an experiment namespace or not.
    static func inNamespace(userId: String, namespace: NameSpace) -> Bool {
        guard let hash = hash(seed: namespace.0, value: userId + "__", version: 1.0) else { return false }
        return inRange(n: hash, range: BucketRange(number1: namespace.1, number2: namespace.2))
    }

    /// Returns an array of floats with numVariations items that are all equal and sum to 1. For example, getEqualWeights(2) would return [0.5, 0.5].
    static func getEqualWeights(numVariations: Int) -> [Float] {
        if numVariations <= 0 { return [] }
        return Array(repeating: 1.0 / Float(numVariations), count: numVariations)
    }

    /// This converts and experiment's coverage and variation weights into an array of bucket ranges.
    static func getBucketRanges(numVariations: Int, coverage: Float, weights: [Float]?) -> [BucketRange] {
        var bucketRange: [BucketRange]

        var targetCoverage = coverage

        // Clamp the value of coverage to between 0 and 1 inclusive.
        if coverage < 0 { targetCoverage = 0 }
        if coverage > 1 { targetCoverage = 1 }

        // Default to equal weights if the weights don't match the number of variations.
        let equal = getEqualWeights(numVariations: numVariations)
        var targetWeights = weights ?? equal
        if targetWeights.count != numVariations {
            targetWeights = equal
        }

        // Default to equal weights if the sum is not equal 1 (or close enough when rounding errors are factored in):
        let weightsSum = targetWeights.sum()
        if weightsSum < 0.99 || weightsSum > 1.01 {
            targetWeights = equal
        }

        // Convert weights to ranges and return
        var cumulative: Float = 0

        bucketRange = targetWeights.map { weight in
            let start = cumulative
            cumulative += weight

            return BucketRange(number1: start.roundTo(numFractionDigits: 4), number2: (start + (targetCoverage * weight)).roundTo(numFractionDigits: 4))
        }

        return bucketRange
    }
    
    static func inRange(n: Float, range: BucketRange) -> Bool {
        return n >= range.number1 && n < range.number2
    }

    /// Choose Variation from List of ranges which matches particular number
    static func chooseVariation(n: Float, ranges: [BucketRange]) -> Int {
        for (index, range) in ranges.enumerated() {
            if inRange(n: n, range: range) {
                return index
            }
        }
        return -1
    }

    /// Convert JsonArray to NameSpace
    static func getGBNameSpace(namespace: [JSON]) -> NameSpace? {
        if namespace.count >= 3 {

            let title = namespace[0].string
            let start = namespace[1].float
            let end = namespace[2].float

            if let title = title, let start = start, let end = end {
                return NameSpace(title, start, end)
            }

        }
        return nil
    }

    static func paddedVersionString(input: String) -> String {
        var parts = input.replacingOccurrences(of: "[v]", with: "", options: .regularExpression)
        
        if let range = parts.range(of: "+")?.lowerBound {
            parts = String(parts.prefix(upTo: range))
        }
        
        let stringArray = parts.components(separatedBy: [".", "-"])
        
        var partArray: [String] = []
        
        for part in stringArray {
            if part != "" {
                partArray.append(part)
            }
        }
        
        if partArray.count == 3 {
            partArray.append("~")
        }
        
        return partArray.map({ $0.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil ? String(repeating: " ", count: 5 - $0.count) + $0 : $0}).joined(separator: "-")
    }
    
    static func convertJsonToDouble(from value: JSON?) -> Double? {
        if let doubleValue = value?.double {
            return doubleValue
        } else if let stringValue = value?.string {
            let doubleFromString = Double(stringValue)
            return doubleFromString
        }
        return nil
    }

    static private func digest(_ string: String) -> UInt32 {
        return Common.fnv1a(Array(string.utf8), offsetBasis: Common.offsetBasis32, prime: Common.prime32)
    }
    
    ///Returns tuple out of 2 elements: the attribute itself an its hash value
    static func getHashAttribute(context: Context, attr: String?, fallback: String? = nil, attributeOverrides: JSON) -> (hashAttribute: String, hashValue: String) {
        var hashAttribute = attr ?? "id"
        var hashValue = ""
        
        if attributeOverrides[hashAttribute] != .null {
            hashValue = attributeOverrides[hashAttribute].stringValue
        } else if context.attributes[hashAttribute] != .null {
            hashValue = context.attributes[hashAttribute].stringValue
        }
        
        // if no match, try fallback
        if let fallback = fallback {
            if attributeOverrides[fallback] != .null {
                hashValue = attributeOverrides[fallback].stringValue
            } else if context.attributes[fallback] != .null {
                hashValue = context.attributes[fallback].stringValue
            }
            
            if !hashValue.isEmpty {
                hashAttribute = fallback
            }
        }
        
        if let fallback = fallback, let fallbackAttributeValue = context.stickyBucketAssignmentDocs?["\(fallback)||\(attributeOverrides[fallback].stringValue)"]?.attributeValue,
           fallbackAttributeValue != attributeOverrides[fallback].stringValue {
            context.stickyBucketAssignmentDocs = [:]
        }
        
        return (hashAttribute, hashValue)
    }
    
    // Returns assignments for StickyAssignmentsDocuments
    static func getStickyBucketAssignments(
        context: Context,
        expHashAttribute: String?,
        expFallbackAttribute: String? = nil,
        attributeOverrides: JSON
    ) -> [String: String] {
        
        guard let stickyBucketAssignmentDocs = context.stickyBucketAssignmentDocs else {
            return [:]
        }
        
         let (hashAttribute, hashValue) = getHashAttribute(
            context: context,
            attr: expHashAttribute,
            fallback: nil,
            attributeOverrides: attributeOverrides
        )
        
        let hashKey = "\(hashAttribute)||\(hashValue)"
        
        let (fallbackAttribute, fallbackValue) = getHashAttribute(
            context: context,
            attr: nil,
            fallback: expFallbackAttribute,
            attributeOverrides: attributeOverrides
        )
        
        let fallbackKey = fallbackValue.isEmpty ? nil : "\(fallbackAttribute)||\(fallbackValue)"
        
        var mergedAssignments: [String: String] = [:]
        
        if let fallbackKey = fallbackKey, let fallbackAssignments = stickyBucketAssignmentDocs[fallbackKey] {
            mergedAssignments.merge(fallbackAssignments.assignments) { (_, new) in new }
        }
        
        if let hashAssignments = stickyBucketAssignmentDocs[hashKey] {
            mergedAssignments.merge(hashAssignments.assignments) { (_, new) in new }
        }
        
        return mergedAssignments
    }
    
    // Update sticky bucketing configuration
    static func refreshStickyBuckets(context: Context, attributeOverrides: JSON, data: FeaturesDataModel?) {
        guard let stickyBucketService = context.stickyBucketService else {
            return
        }
        
        let attributes = getStickyBucketAttributes(context: context, attributeOverrides: attributeOverrides, data: data);
        context.stickyBucketAssignmentDocs = stickyBucketService.getAllAssignments(attributes: attributes)
    }
    
    // Returns hash value for every attribute
    static func getStickyBucketAttributes(context: Context, attributeOverrides: JSON, data: FeaturesDataModel?) -> [String: String] {
        
        var attributes: [String: String] = [:]
        context.stickyBucketIdentifierAttributes = context.stickyBucketIdentifierAttributes != nil
        ? deriveStickyBucketIdentifierAttributes(context: context, data: data)
        : context.stickyBucketIdentifierAttributes
        
        context.stickyBucketIdentifierAttributes?.forEach { attr in
            let hashValue = Utils.getHashAttribute(context: context, attr: attr, attributeOverrides: attributeOverrides)
            attributes[attr] = hashValue.hashValue
        }
        return attributes
    }
    
    // Returns fallback attributes for features that have variations
    static func deriveStickyBucketIdentifierAttributes(context: Context, data: FeaturesDataModel?) -> [String] {
        
        var attributes: Set<String> = []
        
        let features = data?.features ?? context.features
            
        features.keys.forEach({ id in
            let feature = features[id]
            if let rules = feature?.rules {
                for rule in rules {
                    if rule.variations != nil {
                        attributes.insert(rule.hashAttribute ?? "id")
                        if let fallbackAttribute = rule.fallbackAttribute {
                            attributes.insert(fallbackAttribute)
                        }
                    }
                }
            }
        })
        return Array(attributes)
    }
    
    // Get variation of sticky bucketing to use specific functionality
    static func getStickyBucketVariation(
        context: Context,
        experimentKey: String,
        experimentBucketVersion: Int = 0,
        minExperimentBucketVersion: Int = 0,
        meta: [VariationMeta] = [],
        expFallBackAttribute: String? = nil,
        expHashAttribute: String? = "id",
        attributeOverrides: JSON
    ) -> (variation: Int, versionIsBlocked: Bool?) {
        
        let id = getStickyBucketExperimentKey(experimentKey, experimentBucketVersion)
        let assignments = getStickyBucketAssignments(
            context: context,
            expHashAttribute: expHashAttribute,
            expFallbackAttribute: expFallBackAttribute,
            attributeOverrides: attributeOverrides
        )
        
        if minExperimentBucketVersion > 0 {
            for version in 0...minExperimentBucketVersion {
                let blockedKey = getStickyBucketExperimentKey(experimentKey, version)
                if let _ = assignments[blockedKey] {
                    return (variation: -1, versionIsBlocked: true)
                }
            }
        }
        guard let variationKey = assignments[id] else {
            return (variation: -1, versionIsBlocked: nil)
        }
        guard let variation = meta.firstIndex(where: { $0.key == variationKey }) else {
            // invalid assignment, treat as "no assignment found"
            return (variation: -1, versionIsBlocked: nil)
        }
        
        return (variation: variation, versionIsBlocked: nil)
    }
    
    // Get experiment key that is going to use sticky bucketing
    static func getStickyBucketExperimentKey(_ experimentKey: String, _ experimentBucketVersion: Int = 0) -> String {
        return  "\(experimentKey)__\(experimentBucketVersion)" //`${experimentKey}__${experimentBucketVersion}`;
    }
    
    // Create assignment document
    static func generateStickyBucketAssignmentDoc(context: Context, attributeName: String,
                                           attributeValue: String,
                                           assignments: [String: String]) -> (key: String, doc: StickyAssignmentsDocument, changed: Bool) {
        let key = "\(attributeName)||\(attributeValue)"
            let existingAssignments: [String: String] = (context.stickyBucketAssignmentDocs?[key]?.assignments) ?? [:]
            var newAssignments = existingAssignments
            assignments.forEach { newAssignments[$0] = $1 }
        
        let changed = NSDictionary(dictionary: existingAssignments).isEqual(to: newAssignments) == false
        
        return (
                key: key,
                doc: StickyAssignmentsDocument(
                    attributeName: attributeName,
                    attributeValue: attributeValue,
                    assignments: newAssignments
                ),
                changed: changed
            )
    }
    
}
