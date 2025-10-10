//
//  CSSParser.swift
//  Macaw
//
//  Created by Yuri Strot on 10/26/18.
//

import Foundation

#if !CARTHAGE
import SWXMLHash
#endif

private enum SimpleSelector: Hashable {
    case byId(String)
    case byClass(String)
    case byTag(String)
}

private enum Selector {
    case simple(SimpleSelector)
    case descendant(ancestor: SimpleSelector, descendant: SimpleSelector)
}

private struct ClassDescendantKey: Hashable {
    let className: String
    let tag: String
}

class CSSParser {

    fileprivate var stylesByClass: [String: [String: String]] = [:]
    fileprivate var stylesById: [String: [String: String]] = [:]
    fileprivate var stylesByTag: [String: [String: String]] = [:]
    fileprivate var stylesByClassDescendant: [ClassDescendantKey: [String: String]] = [:]

    func parse(content: String) {
        let contentWithoutComments = removeComments(from: content)
        let rules = contentWithoutComments.components(separatedBy: "}")

        for rawRule in rules {
            guard let braceIndex = rawRule.firstIndex(of: "{") else {
                continue
            }

            let selectorPart = rawRule[..<braceIndex]
            let bodyPart = rawRule[rawRule.index(after: braceIndex)...]

            let declarations = parseDeclarations(from: String(bodyPart))
            if declarations.isEmpty {
                continue
            }

            let selectors = selectorPart.split(separator: ",")
            for selectorText in selectors {
                let trimmed = selectorText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let selector = parseSelector(text: trimmed) else {
                    continue
                }
                setStyles(selector: selector, styles: declarations)
            }
        }
    }

    func getStyles(element: SWXMLHash.XMLElement, ancestorClasses: [String]) -> [String: String] {
        var styleAttributes = [String: String]()

        if let styles = stylesByTag[element.name] {
            for (att, val) in styles {
                if styleAttributes.index(forKey: att) == nil {
                    styleAttributes.updateValue(val, forKey: att)
                }
            }
        }

        if let classNamesString = element.allAttributes["class"]?.text {
            let classNames = classNamesString.split(separator: " ")

            classNames.forEach { className in
                let classString = String(className)

                if let styleAttributesFromTable = stylesByClass[classString] {
                    for (att, val) in styleAttributesFromTable {
                        if styleAttributes.index(forKey: att) == nil {
                            styleAttributes.updateValue(val, forKey: att)
                        }
                    }
                }
            }
        }

        if let idString = element.allAttributes["id"]?.text {
            if let styleAttributesFromTable = stylesById[idString] {
                for (att, val) in styleAttributesFromTable {
                    if styleAttributes.index(forKey: att) == nil {
                        styleAttributes.updateValue(val, forKey: att)
                    }
                }
            }
        }

        for className in ancestorClasses {
            let key = ClassDescendantKey(className: className, tag: element.name)
            if let styles = stylesByClassDescendant[key] {
                for (att, val) in styles where styleAttributes.index(forKey: att) == nil {
                    styleAttributes.updateValue(val, forKey: att)
                }
            }
        }

        return styleAttributes
    }

    fileprivate func parseSelector(text: String) -> Selector? {
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        guard let lastToken = tokens.last,
              let descendant = parseSimpleSelector(text: lastToken) else {
            return .none
        }

        if tokens.count == 1 {
            return .simple(descendant)
        }

        if tokens.count == 2,
           let ancestor = parseSimpleSelector(text: tokens[0]) {
            return .descendant(ancestor: ancestor, descendant: descendant)
        }

        return .none
    }

    fileprivate func parseSimpleSelector(text: String) -> SimpleSelector? {
        guard let first = text.first else {
            return .none
        }
        if first == "#" {
            return .byId(String(text.dropFirst()))
        } else if first == "." {
            return .byClass(String(text.dropFirst()))
        }
        return .byTag(text)
    }

    fileprivate func getStyles(selector: SimpleSelector) -> [String: String]? {
        switch selector {
        case .byId(let id):
            return stylesById[id]
        case .byTag(let tag):
            return stylesByTag[tag]
        case .byClass(let name):
            return stylesByClass[name]
        }
    }

    fileprivate func setStyles(selector: Selector, styles: [String: String]) {
        switch selector {
        case .simple(let simpleSelector):
            var currentStyles = getStyles(selector: simpleSelector) ?? [:]
            for (attribute, value) in styles {
                currentStyles[attribute] = value
            }
            setStyles(simpleSelector: simpleSelector, styles: currentStyles)
        case .descendant(let ancestor, let descendant):
            guard case .byClass(let className) = ancestor,
                  case .byTag(let tag) = descendant else {
                return
            }
            let key = ClassDescendantKey(className: className, tag: tag)
            var currentStyles = stylesByClassDescendant[key] ?? [:]
            for (attribute, value) in styles {
                currentStyles[attribute] = value
            }
            stylesByClassDescendant[key] = currentStyles
        }
    }

    fileprivate func setStyles(simpleSelector: SimpleSelector, styles: [String: String]) {
        switch simpleSelector {
        case .byId(let id):
            stylesById[id] = styles
        case .byTag(let tag):
            stylesByTag[tag] = styles
        case .byClass(let name):
            stylesByClass[name] = styles
        }
    }

    fileprivate func parseDeclarations(from body: String) -> [String: String] {
        var declarations: [String: String] = [:]

        let cleaned = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return declarations
        }

        cleaned.split(separator: ";").forEach { attribute in
            let parts = attribute.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if parts.count == 2, !parts[0].isEmpty {
                declarations[parts[0]] = parts[1]
            }
        }

        return declarations
    }

    fileprivate func removeComments(from content: String) -> String {
        var result = content
        while let startRange = result.range(of: "/*"),
              let endRange = result.range(of: "*/", range: startRange.upperBound..<result.endIndex) {
            result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        }
        return result
    }

}
