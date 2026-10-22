# Drawing a node into an existing graphics context

`Node.render(in:size:layout:)` draws directly into a caller-owned `CGContext`, without creating a
native view or an intermediate image. Supply the same top-left coordinate convention used by Macaw
layout, and a positive finite viewport size. For example, a PDF context normally needs a vertical
translation and flip before drawing.

```swift
context.saveGState()
context.translateBy(x: 0, y: pageHeight)
context.scaleBy(x: 1, y: -1)
node.render(in: context, size: Size(w: pageWidth, h: pageHeight))
context.restoreGState()
```

The method preserves the caller's graphics state and does not clear the destination. The root node's
opacity is applied once. Normal shapes remain vector PDF content; embedded images, masks and raster
effects retain their existing behavior. Existing `toNativeImage` behavior is unchanged.

Concurrent calls require independent node trees and contexts. Do not mutate a tree while drawing it
or share a live view's tree with a worker. This is a drawing API, not a synchronization or animation
ownership mechanism.

Validation: `swift test --filter 'NodeContextRenderingTests|GraphicsContextConcurrencyTests|SVGLifetimeTests'` covers
existing destination pixels, transform preservation, root opacity, PDF image resources, independent
worker rendering, temporary scene-graph release, and the existing native-context and SVG lifetime checks.
