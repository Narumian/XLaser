# LaserScriptable Protocol

LaserScriptable defines common semantics for laser assets implemented in multiple programming languages.

JavaScript asset formats are defined in [JavaScriptProtocol.md](JavaScriptProtocol.md).

## Asset metadata

An asset may declare the following metadata:

- `NAME`: a string identifying the asset by name.
- `DESCRIPTION`: a string describing the asset.
- `CATEGORIES`: an array of category strings.
- `TAGS`: an array of tag strings.
- `AUTHOR`: a string identifying the creator.
- `LICENSE`: a string identifying or describing the asset's license.
- `ID`: a string identifying the asset.
- `VERSION`: a string identifying the asset version, separate from the protocol version.

All fields are optional. Category and tag values, identifier formats, version schemes, and license vocabulary are not restricted by this protocol. The host must be able to obtain the declared metadata through the asset descriptor.

## Input declarations

Asset metadata may declare laser inputs and parameters in an `INPUTS` array. Each entry must contain string-valued `NAME` and `TYPE` fields. Numeric inputs may include `DEFAULT`, `MIN`, and `MAX` attributes.
Each input may also include `LABEL`, `DESCRIPTION`, and `UNIT` string fields for display; `NAME` remains the input's programmatic key.
Supported input types include `float`, `int`, `long`, `bool`, `string`, `vec2`, `vec3`, `vec4`, `point2D`, `color`, `enum`, `event`, `array`, `matrix`, `laser`, `image`, `audio`, and `audioFFT`.
`long` is an alias for `int`, and `point2D` is an alias for `vec2`.
The host must be able to obtain an asset descriptor containing its input declarations.
For a declared input, the supplied value must match its type. If no value is supplied, its declared `DEFAULT` is used; otherwise the input is absent.
Defaults are not supported for `laser`, `image`, `audio`, or `audioFFT` inputs.

## Read context

For each read, the host must provide:

- `sampleRate`: the intended output rate in points per second.
- `frameLength`: the desired number of output points for that read.

Both values are hints. The asset is not required to produce exactly `frameLength` points. The host is responsible for any final adjustment required by the output.

## Output

The host provides a reusable output buffer for the asset to write into. The output represents 3D shapes before projection.

Each shape has an identifier and a range of vertices. Each vertex has a four-component position, a four-component RGBA color, and a point mode: normal, dwell, or blank.

Each shape also has a model matrix and a tint. The model matrix is a 4×4 matrix, defaulting to identity. The tint is an RGBA color, defaulting to white (1, 1, 1, 1). Vertex positions are in the shape's local space. The host applies the model matrix to every vertex position, and multiplies every vertex color component by the tint, when it converts the shapes to the output space. Both are evaluated once per shape rather than being written into the vertices.

The output supports a variable number of shapes and vertices. `frameLength` is a hint, not a strict output limit.

## Input

An asset's laser inputs use the same 3D shape representation as its output. Each read operates on the shape data provided for that read.
The host applies each input shape's model matrix and tint to its vertices before the read, so every input shape has an identity model matrix and a white tint.
Inputs are read-only and valid only during the current read. The asset must not modify inputs or retain references to them after the read. Behavior on violation is undefined.

## Buffer management

The host provides and manages the input and output buffers. The asset must be able to request output buffer growth through a host-provided mechanism.
Growing the output buffer preserves its contents. The output object remains the same, but any previously obtained output buffer views become invalid; the asset must obtain new views after growth.
The asset must fully write the position and color components of every vertex it commits.
A read's output is valid until the next read for that asset begins. To retain it longer, the host must copy it or use another buffer.

## Vertex precision

Position and color components, model matrices, and tints use 32-bit floating-point values. They must be finite.

## Execution errors

If a read fails, its output must not be used and the asset must stop. The host may reinitialize the asset before running it again.

Recoverable asset loading and execution errors must be reported to the host. Invalid input or output originating from an asset must not be handled with native assertions or fatal errors.

## Open concerns

Execution time limits, including interruption of infinite loops, and memory limits require investigation for each engine and platform. Recovery from process-level failures is not guaranteed.

## Playback time

For each read, the host must provide `context.time` in seconds as the playback time assigned to that read’s output.
