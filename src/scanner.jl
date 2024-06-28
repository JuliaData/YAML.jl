# YAML 1.1 [27] b-char ::= b-line-feed | b-carriage-return | b-next-line | b-line-separator | b-paragraph-separator
is_b_char(::YAMLV1_1, c::Char) = c == '\n' || c == '\r' || c == '\u85' || c == '\u2028' || c == '\u2029'

# YAML 1.2 [31] s-space ::= x20
const yaml_1_2_s_space = ' '
# YAML 1.2 [32] s-tab ::= x09
const yaml_1_2_s_tab = '\t'
# YAML 1.1 [36] s-white ::= #x9 /*TAB*/ | #x20 /*SP*/
# YAML 1.2 [33] s-white ::= s-space | s-tab
is_s_white(c::Char) = c == yaml_1_2_s_space || c == yaml_1_2_s_tab

# YAML 1.1 [40] ns-hex-digit ::= ns-dec-digit | [#x41-#x46] /*A-F*/ | [#x61-#x66] /*a-f*/
# YAML 1.2 [36] ns-hex-digit ::= ns-dec-digit | [x41-x46] | [x61-x66] # 0-9 A-F a-f
is_ns_hex_digit(c::Char) = isdigit(c) || 'A' ≤ c ≤ 'F' || 'a' ≤ c ≤ 'f'

# YAML 1.1 [41] ns-ascii-letter ::= [#x41-#x5A] /*A-Z*/ | [#61-#x7A] /*a-z*/
# YAML 1.2 [37] ns-ascii-letter ::= [x41-x5A] | [x61-x7A] # A-Z a-z
is_ns_ascii_letter(c::Char) = 'A' ≤ c ≤ 'Z' || 'a' ≤ c ≤ 'z'

is_whitespace(::YAMLV1_1, c::Char) = c == '\0' || c == ' ' || c == '\t' || is_b_char(YAMLV1_1(), c)

struct SimpleKey
    token_number::UInt64
    required::Bool
    mark::Mark
end


# Errors thrown by the scanner.
struct ScannerError <: Exception
    context::Union{String, Nothing}
    context_mark::Union{Mark, Nothing}
    problem::String
    problem_mark::Mark
end

function show(io::IO, error::ScannerError)
    if error.context !== nothing
        print(io, error.context, " at ", error.context_mark, ": ")
    end
    print(io, error.problem, " at ", error.problem_mark)
end


function detect_encoding(input::IO)::Encoding
    pos = position(input)
    start_bytes = Array{UInt8}(undef, 4)
    bytes_read = readbytes!(input, start_bytes, 4)
    seek(input, pos)

    start_bytes[bytes_read+1:end] .= 1  #fill blanks with non-special bytes
    intro = UInt32(start_bytes[4]) << 24 +
        UInt32(start_bytes[3]) << 16 +
        UInt32(start_bytes[2]) << 8 +
        UInt32(start_bytes[1])

    # https://yaml.org/spec/1.2/spec.html#id2771184
    if intro & 0x00ffffff == 0xbfbbef  #utf-8 bom
        enc"UTF-8"
    elseif intro == 0xfffe0000  #utf-32be BOM
        enc"UTF-32BE"
    elseif intro == 0x0000feff  #utf-32le BOM
        enc"UTF-32LE"
    elseif intro & 0xffff == 0xfffe  #utf-16be BOM
        enc"UTF-16BE"
    elseif intro & 0xffff == 0xfeff  #utf-16le BOM
        enc"UTF-16LE"
    elseif intro & 0x00ffffff == 0  #ascii char in utf-32be
        enc"UTF-32BE"
    elseif intro & 0xffffff00 == 0  #ascii char in utf-32le
        enc"UTF-32LE"
    elseif intro & 0x00ff == 0  #ascii char in utf-16be
        enc"UTF-16BE"
    elseif intro & 0xff00 == 0  #ascii char in utf-16le
        enc"UTF-16LE"
    else
        enc"UTF-8"
    end
end


# A stream type for the scanner, which is just a IO stream with scanner state.
mutable struct TokenStream
    input::BufferedInput

    encoding::Encoding

    # All tokens read.
    done::Bool

    # Tokens queued to be read.
    token_queue::Queue{Token}

    # Index of the start of the head of the stream. (0-based)
    index::UInt64

    # Index of the current column. (0-based)
    column::UInt64

    # Current line numebr. (0-based)
    line::UInt64

    # Number of tokens read, not including those still in token_queue.
    tokens_taken::UInt64

    # The number of unclosed '{' and '['. `flow_level == 0` means block
    # context.
    flow_level::UInt64

    # Current indentation level.
    indent::Int

    # Past indentation levels.
    indents::Vector{Int}

    # Can a simple key start at the current position? A simple key may
    # start:
    # - at the beginning of the line, not counting indentation spaces
    #       (in block context),
    # - after '{', '[', ',' (in the flow context),
    # - after '?', ':', '-' (in the block context).
    # In the block context, this flag also signifies if a block collection
    # may start at the current position.
    allow_simple_key::Bool

    # Keep track of possible simple keys. This is a dictionary. The key
    # is `flow_level`; there can be no more that one possible simple key
    # for each level. The value is a SimpleKey record:
    #   (token_number, required, index, line, column, mark)
    # A simple key may start with ALIAS, ANCHOR, TAG, SCALAR(flow),
    # '[', or '{' tokens.
    possible_simple_keys::Dict{UInt64,SimpleKey}

    function TokenStream(stream::IO)
        encoding = detect_encoding(stream)
        decoded_stream = encoding == enc"UTF-8" ? stream : StringDecoder(stream, encoding)
        tokstream = new(BufferedInput(decoded_stream),
                        encoding, false, Queue{Token}(),
                        1, 0, 1, 0, 0, -1,
                        Int[], true, Dict())
        fetch_stream_start(tokstream)
        tokstream
    end
end


function reset!(stream::TokenStream)
    stream.done = false
    fetch_stream_start(stream)
end


function get_mark(stream::TokenStream)
    Mark(stream.index, stream.line, stream.column)
end


# Advance the stream by k characters.
function forwardchars!(stream::TokenStream, k::Integer=1)
    for _ in 1:k
        c = peek(stream.input)
        forward!(stream.input)
        stream.index += 1
        if in(c, "\n\u0085\u2028\u2029") ||
            (c == '\r' && peek(stream.input) == '\n')
            stream.column = 0
            stream.line += 1
        else
            stream.column += 1
        end
    end
    stream.index += k
    nothing
end


function need_more_tokens(stream::TokenStream)
    if stream.done
        return false
    elseif isempty(stream.token_queue)
        return true
    end

    stale_possible_simple_keys(stream)
    next_possible_simple_key(stream) == stream.tokens_taken
end

# peek the first token from the token stream
function peek(stream::TokenStream)::Union{Token, Nothing}
    while need_more_tokens(stream)
        fetch_more_tokens(stream)
    end

    if !isempty(stream.token_queue)
        peek(stream.token_queue)
    else
        nothing
    end
end

# advance and return the first token from the token stream
function forward!(stream::TokenStream)::Union{Token, Nothing}
    while need_more_tokens(stream)
        fetch_more_tokens(stream)
    end

    if !isempty(stream.token_queue)
        stream.tokens_taken += 1
        dequeue!(stream.token_queue)
    else
        nothing
    end
end


# Read one or more tokens from the input stream.
function fetch_more_tokens(stream::TokenStream)
    # Eat whitespace.
    scan_to_next_token(stream::TokenStream)

    # Remove obsolete possible simple keys.
    stale_possible_simple_keys(stream)

    # Compare the current indentation and column. It may add some tokens
    # and decrease the current indentation level.
    unwind_indent(stream, stream.column)

    c = peek(stream.input)
    if c == '\0' || c === nothing
        fetch_stream_end(stream)
    elseif c == '%' && check_directive(stream)
        fetch_directive(stream)
    elseif c == '-' && check_document_start(stream)
        fetch_document_start(stream)
    elseif c == '.' && check_document_end(stream)
        fetch_document_end(stream)
        stream.done = true
    elseif c == '['
        fetch_flow_sequence_start(stream)
    elseif c == '{'
        fetch_flow_mapping_start(stream)
    elseif c == ']'
        fetch_flow_sequence_end(stream)
    elseif c == '}'
        fetch_flow_mapping_end(stream)
    elseif c == ','
        fetch_flow_entry(stream)
    elseif c == '-' && check_block_entry(stream)
        fetch_block_entry(stream)
    elseif c == '?' && check_key(stream)
        fetch_key(stream)
    elseif c == ':' && check_value(stream)
        fetch_value(stream)
    elseif c == '*'
        fetch_alias(stream)
    elseif c == '&'
        fetch_anchor(stream)
    elseif c == '!'
        fetch_tag(stream)
    elseif c == '|' && stream.flow_level == 0
        fetch_literal(stream)
    elseif c == '>' && stream.flow_level == 0
        fetch_folded(stream)
    elseif c == '\''
        fetch_single(stream)
    elseif c == '\"'
        fetch_double(stream)
    elseif c == '\uFEFF'
        fetch_byte_order_mark(stream)
    elseif check_plain(stream)
        fetch_plain(stream)
    else
        throw(ScannerError(nothing, nothing,
                           "while scanning for the next token, found character '$c' that cannot start any token",
                           get_mark(stream)))
    end
end


# Simple keys
# -----------

# Return the number of the nearest possible simple key.
function next_possible_simple_key(stream::TokenStream)
    min_token_number = nothing
    for (level, key) in stream.possible_simple_keys
        key = stream.possible_simple_keys[level]
        if min_token_number === nothing || key.token_number < min_token_number
            min_token_number = key.token_number
        end
    end
    min_token_number
end


# Remove entries that are no longer possible simple keys. According to
# the YAML specification, simple keys
# - should be limited to a single line,
# - should be no longer than 1024 characters.
# Disabling this procedure will allow simple keys of any length and
# height (may cause problems if indentation is broken though).
function stale_possible_simple_keys(stream::TokenStream)
    for (level, key) in stream.possible_simple_keys
        if key.mark.line != stream.line || stream.index - key.mark.index > 1024
            if key.required
                throw(ScannerError("while scanning a simple key", key.mark,
                      "could not find expected ':'", get_mark(stream)))
            end
            delete!(stream.possible_simple_keys, level)
        end
    end
end


function save_possible_simple_key(stream::TokenStream)
    # Simple key required at the current position.
    required = stream.flow_level == 0 && stream.indent == stream.column
    @assert stream.allow_simple_key || !required

    if stream.allow_simple_key
        remove_possible_simple_key(stream)
        token_number = stream.tokens_taken + length(stream.token_queue)
        key = SimpleKey(token_number, required, get_mark(stream))
        stream.possible_simple_keys[stream.flow_level] = key
    end
end


function remove_possible_simple_key(stream::TokenStream)
    # Remove the saved possible key position at the current flow level.
    if haskey(stream.possible_simple_keys, stream.flow_level)
        key = stream.possible_simple_keys[stream.flow_level]
        if key.required
            throw(ScannerError("while scanning a simple key", key.mark,
                               "could not find expected ':'", get_mark(stream)))
        end
        delete!(stream.possible_simple_keys, stream.flow_level)
    end
end


function unwind_indent(stream::TokenStream, column)
    # In the flow context, indentation is ignored. We make the scanner less
    # restrictive than specification requires.
    if stream.flow_level != 0
        return
    end

    # In block context, we may need to issue the BLOCK-END tokens.
    while stream.indent > column
        mark = get_mark(stream)
        stream.indent = pop!(stream.indents)
        enqueue!(stream.token_queue, BlockEndToken(Span(mark, mark)))
    end
end


function add_indent(stream::TokenStream, column)
    if stream.indent < column
        push!(stream.indents, stream.indent)
        stream.indent = column
        true
    else
        false
    end
end



# Checkers
# --------


function check_directive(stream::TokenStream)
    stream.column == 0
end

function check_document_start(stream::TokenStream)
    stream.column == 0 &&
        prefix(stream.input, 3) == "---" &&
        is_whitespace(YAMLV1_1(), peek(stream.input, 3))
end

 function check_document_end(stream::TokenStream)
     stream.column == 0 &&
     prefix(stream.input, 3) == "..." &&
    (is_whitespace(YAMLV1_1(), peek(stream.input, 3)) || peek(stream.input, 3) === nothing)
 end

function check_block_entry(stream::TokenStream)
    is_whitespace(YAMLV1_1(), peek(stream.input, 1))
end

function check_key(stream::TokenStream)
    stream.flow_level > 0 || is_whitespace(YAMLV1_1(), peek(stream.input, 1))
end

function check_value(stream::TokenStream)
    cnext = peek(stream.input, 1)
    stream.flow_level > 0 || is_whitespace(YAMLV1_1(), cnext) || cnext === nothing
end

function check_plain(stream::TokenStream)
    !in(peek(stream.input), "\0 \t\r\n\u0085\u2028\u2029-?:,[]{}#&*!|>\'\"%@`\uFEFF") ||
    (!is_whitespace(YAMLV1_1(), peek(stream.input, 1)) &&
     (peek(stream.input) == '-' || (stream.flow_level == 0 &&
                              in(peek(stream.input), "?:"))))
end


# Fetchers
# --------

function fetch_stream_start(stream::TokenStream)
    mark = get_mark(stream)
    enqueue!(stream.token_queue,
             StreamStartToken(Span(mark, mark), string(stream.encoding)))
end


function fetch_stream_end(stream::TokenStream)
    # Set the current intendation to -1.
    unwind_indent(stream, -1)

    # Reset simple keys.
    remove_possible_simple_key(stream)
    stream.allow_simple_key = false
    empty!(stream.possible_simple_keys)

    mark = get_mark(stream)
    enqueue!(stream.token_queue, StreamEndToken(Span(mark, mark)))
    stream.done = true
end


function fetch_directive(stream::TokenStream)
    # Set the current intendation to -1.
    unwind_indent(stream, -1)

    # Reset simple keys.
    remove_possible_simple_key(stream)
    stream.allow_simple_key = false

    enqueue!(stream.token_queue, scan_directive(stream))
end


function fetch_document_start(stream::TokenStream)
    fetch_document_indicator(stream, DocumentStartToken)
end


function fetch_document_end(stream::TokenStream)
    fetch_document_indicator(stream, DocumentEndToken)
end


function fetch_document_indicator(stream::TokenStream, ::Type{T}) where {T<:Token}
    # Set the current intendation to -1.
    unwind_indent(stream, -1)

    # Reset simple keys. Note that there could not be a block collection
    # after '---'.
    remove_possible_simple_key(stream)
    stream.allow_simple_key = false

    # Add DOCUMENT-START or DOCUMENT-END.
    start_mark = get_mark(stream)
    forwardchars!(stream, 3)
    end_mark = get_mark(stream)
    enqueue!(stream.token_queue, T(Span(start_mark, end_mark)))
end


function fetch_byte_order_mark(stream::TokenStream)
    # Set the current intendation to -1.
    unwind_indent(stream, -1)

    start_mark = get_mark(stream)
    forward!(stream.input)
    stream.index += 1
    end_mark = get_mark(stream)
    enqueue!(stream.token_queue, ByteOrderMarkToken(Span(start_mark, end_mark)))
end


function fetch_flow_sequence_start(stream::TokenStream)
    fetch_flow_collection_start(stream, FlowSequenceStartToken)
end


function fetch_flow_mapping_start(stream::TokenStream)
    fetch_flow_collection_start(stream, FlowMappingStartToken)
end


function fetch_flow_collection_start(stream::TokenStream, ::Type{T}) where {T<:Token}
    # '[' and '{' may start a simple key.
    save_possible_simple_key(stream)

    # Increase the flow level.
    stream.flow_level += 1

    # Simple keys are allowed after '[' and '{'.
    stream.allow_simple_key = true


    # Add FLOW-SEQUENCE-START or FLOW-MAPPING-START.
    start_mark = get_mark(stream)
    forwardchars!(stream)
    end_mark = get_mark(stream)
    enqueue!(stream.token_queue, T(Span(start_mark, end_mark)))
end


function fetch_flow_sequence_end(stream::TokenStream)
    fetch_flow_collection_end(stream, FlowSequenceEndToken)
end


function fetch_flow_mapping_end(stream::TokenStream)
    fetch_flow_collection_end(stream, FlowMappingEndToken)
end


function fetch_flow_collection_end(stream::TokenStream, ::Type{T}) where {T<:Token}
    # Reset possible simple key on the current level.
    remove_possible_simple_key(stream)

    # Decrease the flow level.
    stream.flow_level -= 1

    # No simple keys after ']' or '}'.
    stream.allow_simple_key = false

    # Add FLOW-SEQUENCE-END or FLOW-MAPPING-END.
    start_mark = get_mark(stream)
    forwardchars!(stream)
    end_mark = get_mark(stream)
    enqueue!(stream.token_queue, T(Span(start_mark, end_mark)))
end


function fetch_flow_entry(stream::TokenStream)
    # Simple keys are allowed after ','.
    stream.allow_simple_key = true

    # Reset possible simple key on the current level.
    remove_possible_simple_key(stream)

    # Add FLOW-ENTRY.
    start_mark = get_mark(stream)
    forwardchars!(stream)
    end_mark = get_mark(stream)
    enqueue!(stream.token_queue, FlowEntryToken(Span(start_mark, end_mark)))
end


function fetch_block_entry(stream::TokenStream)
    # Block context needs additional checks.
    if stream.flow_level == 0
        # Are we allowed to start a new entry?
        if !stream.allow_simple_key
            throw(ScannerError(nothing, nothing,
                               "sequence entries not allowed here",
                               get_mark(stream)))
        end

        if add_indent(stream, stream.column)
            mark = get_mark(stream)
            enqueue!(stream.token_queue,
                     BlockSequenceStartToken(Span(mark, mark)))
        end

    # It's an error for the block entry to occur in the flow context,
    # but we let the parser detect this.
    else
        return
    end

    # Simple keys are allowed after '-'.
    stream.allow_simple_key = true

    # Reset possible simple key on the current level.
    remove_possible_simple_key(stream)

    # Add BLOCK-ENTRY.
    start_mark = get_mark(stream)
    forwardchars!(stream)
    end_mark = get_mark(stream)
    enqueue!(stream.token_queue,
             BlockEntryToken(Span(start_mark, end_mark)))
end


function fetch_key(stream::TokenStream)
    if stream.flow_level == 0
        # Are we allowed to start a key (not nessesary a simple)?
        if !stream.allow_simple_key
            throw(ScannerError(nothing, nothing,
                               "mapping keys are not allowed here",
                               get_mark(stream)))
        end

        # We may need to add BLOCK-MAPPING-START.
        if add_indent(stream, stream.column)
            mark = get_mark(stream)
            enqueue!(stream.token_queue,
                     BlockMappingStartToken(Span(mark, mark)))
        end
    end

    # Simple keys are allowed after '?' in the block context.
    stream.allow_simple_key = stream.flow_level == 0

    # Reset possible simple key on the current level.
    remove_possible_simple_key(stream)

    # Add KEY.
    start_mark = get_mark(stream)
    forwardchars!(stream)
    end_mark = get_mark(stream)
    enqueue!(stream.token_queue, KeyToken(Span(start_mark, end_mark)))
end


function fetch_value(stream::TokenStream)
    # Simple key
    if haskey(stream.possible_simple_keys, stream.flow_level)
        # Add KEY.
        key = stream.possible_simple_keys[stream.flow_level]
        delete!(stream.possible_simple_keys, stream.flow_level)

        enqueue!(stream.token_queue, KeyToken(Span(key.mark, key.mark)),
                 key.token_number - stream.tokens_taken)

        # If this key starts a new block mapping, we need to add
        # BLOCK-MAPPING-START.
        if stream.flow_level == 0 && add_indent(stream, key.mark.column)
            enqueue!(stream.token_queue,
                     BlockMappingStartToken(Span(key.mark, key.mark)),
                     key.token_number - stream.tokens_taken)
        end

        stream.allow_simple_key = false

    # Complex key
    else
        # Block context needs additional checks.
        # (Do we really need them? They will be caught by the parser
        # anyway.)
        if stream.flow_level == 0
            # We are allowed to start a complex value if and only if
            # we can start a simple key.
            if !stream.allow_simple_key
                throw(ScannerError(nothing, nothing,
                                   "mapping values are not allowed here",
                                   get_mark(stream)))
            end
        end

        # If this value starts a new block mapping, we need to add
        # BLOCK-MAPPING-START.  It will be detected as an error later by
        # the parser.
        if stream.flow_level == 0 && add_indent(stream, stream.column)
            mark = get_mark(stream)
            enqueue!(stream.token_queue,
                     BlockMappingStartToken(Span(mark, mark)))
        end

        # Simple keys are allowed after ':' in the block context.
        stream.allow_simple_key = stream.flow_level == 0

        # Reset possible simple key on the current level.
        remove_possible_simple_key(stream)
    end

    # Add VALUE.
    start_mark = get_mark(stream)
    forwardchars!(stream)
    end_mark = get_mark(stream)
    enqueue!(stream.token_queue, ValueToken(Span(start_mark, end_mark)))
end


function fetch_alias(stream::TokenStream)
    # ALIAS could be a simple key.
    save_possible_simple_key(stream)

    # No simple keys after ALIAS.
    stream.allow_simple_key = false

    # Scan and add ALIAS.
    enqueue!(stream.token_queue, scan_anchor(stream, AliasToken))
end


function fetch_anchor(stream::TokenStream)
    # ANCHOR could start a simple key.
    save_possible_simple_key(stream)

    # No simple keys after ANCHOR.
    stream.allow_simple_key = false

    # Scan and add ANCHOR.
    enqueue!(stream.token_queue, scan_anchor(stream, AnchorToken))
end


function fetch_tag(stream::TokenStream)
    # TAG could start a simple key.
    save_possible_simple_key(stream)

    # No simple keys after TAG.
    stream.allow_simple_key = false

    # Scan and add TAG.
    enqueue!(stream.token_queue, scan_tag(stream))
end


function fetch_literal(stream::TokenStream)
    fetch_block_scalar(stream, '|')
end


function fetch_folded(stream::TokenStream)
    fetch_block_scalar(stream, '>')
end


function fetch_block_scalar(stream::TokenStream, style::Char)
    # A simple key may follow a block scalar.
    stream.allow_simple_key = true

    # Reset possible simple key on the current level.
    remove_possible_simple_key(stream)

    # Scan and add SCALAR.
    enqueue!(stream.token_queue, scan_block_scalar(stream, style))
end


function fetch_single(stream::TokenStream)
    fetch_flow_scalar(stream, '\'')
end


function fetch_double(stream::TokenStream)
    fetch_flow_scalar(stream, '"')
end


function fetch_flow_scalar(stream::TokenStream, style::Char)
    # A flow scalar could be a simple key.
    save_possible_simple_key(stream)

    # No simple keys after flow scalars.
    stream.allow_simple_key = false

    # Scan and add SCALAR.
    enqueue!(stream.token_queue, scan_flow_scalar(stream, style))
end


function fetch_plain(stream::TokenStream)
    save_possible_simple_key(stream)
    stream.allow_simple_key = false
    enqueue!(stream.token_queue, scan_plain(stream))
end


# Scanners
# --------

# If the stream is at a line break, advance past it.
#
# YAML 1.1
#
# [22] b-line-feed           ::= #xA /*LF*/
# [23] b-carriage-return     ::= #xD /*CR*/
# [24] b-next-line           ::= #x85 /*NEL*/
# [25] b-line-separator      ::= #x2028 /*LS*/
# [26] b-paragraph-separator ::= #x2029 /*PS*/
# [28] b-specific            ::= b-line-separator | b-paragraph-separator
# [29] b-generic             ::= ( b-carriage-return b-line-feed) | b-carriage-return | b-line-feed | b-next-line
# [30] b-as-line-feed        ::= b-generic
# [31] b-normalized          ::= b-as-line-feed | b-specific
#
# U+000D U+000A → U+000A
# U+000D        → U+000A
# U+000A        → U+000A
# U+0085        → U+000A
# U+2028        → U+2028
# U+2029        → U+2029
# otherwise     → (empty)
#
function scan_line_break(::YAMLV1_1, stream::TokenStream)::String
    c = peek(stream.input)
    if c == '\u000d'
        if peek(stream.input, 1) == '\u000a'
            forwardchars!(stream, 2)
        else
            forwardchars!(stream)
        end
        "\u000a"
    elseif c == '\u000a' || c == '\u0085'
        forwardchars!(stream)
        "\u000a"
    elseif c == '\u2028' || c == '\u2029'
        forwardchars!(stream)
        string(c)
    else
        ""
    end
end
#
# YAML 1.2
#
# [24] b-line-feed       ::= x0A
# [25] b-carriage-return ::= x0D
# [26] b-char            ::= b-line-feed | b-carriage-return
# [27] nb-char           ::= c-printable - b-char - c-byte-order-mark
# [28] b-break           ::= ( b-carriage-return b-line-feed ) | b-carriage-return | b-line-feed
#
# U+000D U+000A → U+000A
# U+000D        → U+000A
# U+000A        → U+000A
# otherwise     → (empty)
#
function scan_line_break(::YAMLV1_2, stream::TokenStream)::String
    c = peek(stream.input)
    if c == '\u000d'
        if peek(stream.input, 1) == '\u000a'
            forwardchars!(stream, 2)
        else
            forwardchars!(stream)
        end
        "\u000a"
    elseif c == '\u000a'
        forwardchars!(stream)
        "\u000a"
    else
        ""
    end
end

# Scan past whitespace to the next token.
function scan_to_next_token(stream::TokenStream)
    while true
        # whitespace
        while peek(stream.input) == ' '
            forwardchars!(stream)
        end
        # comment
        if peek(stream.input) == '#'
            forwardchars!(stream)
            while !in(peek(stream.input), "\0\r\n\u0085\u2028\u2029")
                forwardchars!(stream)
            end
        end
        # line break
        if scan_line_break(YAMLV1_1(), stream) != ""
            if stream.flow_level == 0
                stream.allow_simple_key = true
            end
        # found a token
        else
            break
        end
    end
end


function scan_directive(stream::TokenStream)
    start_mark = get_mark(stream)
    forwardchars!(stream)
    name = scan_directive_name(stream, start_mark)

    value = nothing
    if name == "YAML"
        value = scan_yaml_directive_value(stream, start_mark)
        end_mark = get_mark(stream)
    elseif name == "TAG"
        tag_handle = scan_tag_directive_handle(stream, start_mark)
        tag_prefix = scan_tag_directive_prefix(stream, start_mark)
        value = (tag_handle, tag_prefix)
        end_mark = get_mark(stream)
    else
        # Otherwise we warn and ignore the directive.
        end_mark = get_mark(stream)
        @warn """unknown directive name: "$name" at $end_mark. We ignore this."""
        while !in(peek(stream.input), "\0\r\n\u0085\u2028\u2029")
            forwardchars!(stream)
        end
    end

    scan_directive_ignored_line(stream, start_mark)
    DirectiveToken(Span(start_mark, end_mark), name, value)
end


function scan_directive_name(stream::TokenStream, start_mark::Mark)
    length = 0
    c = peek(stream.input)
    while is_ns_ascii_letter(c) || isdigit(c) || c == '-' || c == '_'
        length += 1
        c = peek(stream.input, length)
    end

    if length == 0
        throw(ScannerError("while scanning a directive", start_mark,
                           "expected alphanumeric character, but found '$(c)'",
                           get_mark(stream)))
    end

    value = prefix(stream.input, length)
    forwardchars!(stream, length)

    c = peek(stream.input)
    if !in(c, ":\0 \r\n\u0085\u2028\u2029")
        throw(ScannerError("while scanning a directive", start_mark,
                           "expected alphanumeric character, but found '$(c)'",
                           get_mark(stream)))
    end

    value
end


function scan_yaml_directive_value(stream::TokenStream, start_mark::Mark)
    while peek(stream.input) == ' ' || peek(stream.input) == ':'
        forwardchars!(stream)
    end

    major = scan_yaml_directive_number(stream, start_mark)
    if peek(stream.input) != '.'
        throw(ScannerError("while scanning a directive", start_mark,
                           "expected '.' but found '$(peek(stream.input))'",
                           get_mark(stream)))
    end
    forwardchars!(stream)
    minor = scan_yaml_directive_number(stream, start_mark)
    if !in(peek(stream.input), "\0 \r\n\u0085\u2028\u2029")
        throw(ScannerError("while scanning a directive", start_mark,
                           "expected ' ' or a line break, but found '$(peek(stream.input))'",
                           get_mark(stream)))
    end
    return (major, minor)
end


# scan the YAML directive's number from a stream
function scan_yaml_directive_number(stream::TokenStream, start_mark::Mark)::Int
    # -------------------------------------------------
    # check that the first character is a decimal digit
    # -------------------------------------------------
    # the current position of the character in the stream
    pos = 0
    # the current character
    c = peek(stream.input, pos)
    # throw an error if the input is not decimal digits
    isdigit(c) || throw(ScannerError(
        "while scanning a directive", start_mark,
        "expected a digit, but found '$c'", get_mark(stream),
    ))
    # -----------------------------------------------------------
    # until the end of the decimal digits, increment the position
    # -----------------------------------------------------------
    while true
        pos += 1
        c = peek(stream.input, pos)
        isdigit(c) || break
    end
    # ------------------------------
    # get the decimal digit as `Int`
    # ------------------------------
    # the decimal digit as a `String`
    str = prefix(stream.input, pos)
    # the decimal digit as an `Int`
    n = parse(Int, str)
    # ---------------------------------------------------
    # advance the stream by the length that has been read
    # ---------------------------------------------------
    forwardchars!(stream, pos)
    # -----------------
    # return the number
    # -----------------
    n
end


function scan_tag_directive_handle(stream::TokenStream, start_mark::Mark)
    while peek(stream.input) == ' '
        forwardchars!(stream)
    end

    value = scan_tag_handle(stream, "directive", start_mark)
    if peek(stream.input) != ' '
        throw(ScannerError("while scanning a directive", start_mark,
                           "expected ' ', but found '$(peek(stream.input))'",
                           get_mark(stream)))
    end
    value
end


function scan_tag_directive_prefix(stream::TokenStream, start_mark::Mark)
    while peek(stream.input) == ' '
        forwardchars!(stream)
    end

    value = scan_tag_uri(stream, "directive", start_mark)
    if !in(peek(stream.input), "\0 \r\n\u0085\u2028\u2029")
        throw(ScannerError("while scanning a directive", start_mark,
                           "expected ' ', but found $(peek(stream.input))",
                           get_mark(stream)))
    end
    value
end


function scan_directive_ignored_line(stream::TokenStream, start_mark::Mark)
    while peek(stream.input) == ' '
        forwardchars!(stream)
    end
    if peek(stream.input) == '#'
        forwardchars!(stream)
        while !in(peek(stream.input), "\0\r\n\u0085\u2028\u2029")
            forwardchars!(stream)
        end
    end
    if !in(peek(stream.input), "\0\r\n\u0085\u2028\u2029")
        throw(ScannerError("while scanning a directive", start_mark,
                           "expected a comment or a line break, but found '$(peek(stream.input))'",
                           get_mark(stream)))
    end
    scan_line_break(YAMLV1_1(), stream)
end


function scan_anchor(stream::TokenStream, ::Type{T}) where {T<:Token}
    start_mark = get_mark(stream)
    indicator = peek(stream.input)
    if indicator == '*'
        name = "alias"
    else
        name = "anchor"
    end
    forwardchars!(stream)
    length = 0
    c = peek(stream.input)
    while is_ns_ascii_letter(c) || isdigit(c) || c == '-' || c == '_'
        length += 1
        c = peek(stream.input, length)
    end

    if length == 0
        throw(ScannerError("while scanning an $(name)", start_mark,
                           "expected an alphanumeric character, but found '$(peek(stream.input))'",
                           get_mark(stream)))
    end
    value = prefix(stream.input, length)
    forwardchars!(stream, length)
    if !in(peek(stream.input), "\0 \t\r\n\u0085\u2028\u2029?:,]}%@`")
        throw(ScannerError("while scanning an $(name)", start_mark,
                           "expected an alphanumeric character, but found '$(peek(stream.input))'",
                           get_mark(stream)))
    end
    end_mark = get_mark(stream)
    T(Span(start_mark, end_mark), value)
end


function scan_tag(stream::TokenStream)
    start_mark = get_mark(stream)
    c = peek(stream.input, 1)
    if c == '<'
        handle = nothing
        forwardchars!(stream, 2)
        suffix = scan_tag_uri(stream, "tag", start_mark)
        if peek(stream.input) != '>'
            throw(ScannerError("while parsing a tag", start_mark,
                               "expected '>', but found '$(peek(stream.input))'",
                               get_mark(stream)))
        end
        forwardchars!(stream)
    elseif in(c, "\0 \t\r\n\u0085\u2028\u2029")
        handle = nothing
        suffix = '!'
        forwardchars!(stream)
    else
        length = 1
        use_handle = false
        while !in(c, "\0 \r\n\u0085\u2028\u2029")
            if c == '!'
                use_handle = true
                break
            end
            length += 1
            c = peek(stream.input, length)
        end
        if use_handle
            handle = scan_tag_handle(stream, "tag", start_mark)
        else
            handle = "!"
            forwardchars!(stream)
        end
        suffix = scan_tag_uri(stream, "tag", start_mark)
    end

    c = peek(stream.input)
    if !in(c, "\0 \r\n\u0085\u2028\u2029")
        throw(ScannerError("while scanning a tag", start_mark,
                           "expected ' ' or a line break, but found '$(c)'",
                           get_mark(stream)))
    end

    value = (handle, suffix)
    end_mark = get_mark(stream)
    TagToken(Span(start_mark, end_mark), value)
end


function scan_block_scalar(stream::TokenStream, style::Char)
    folded = style == '>'

    chunks = Any[]
    start_mark = get_mark(stream)

    # Scan the header.
    forwardchars!(stream)
    chomping, increment = scan_block_scalar_indicators(stream, start_mark)
    scan_block_scalar_ignored_line(stream, start_mark)

    # Determine the indentation level and go to the first non-empty line.
    min_indent = max(1, stream.indent + 1)
    if increment === nothing
        breaks, max_indent, end_mark = scan_block_scalar_indentation(stream)
        indent = max(min_indent, max_indent)
    else
        indent = min_indent + increment - 1
        breaks, end_mark = scan_block_scalar_breaks(stream, indent)
    end
    line_break = ""

    # Scan the inner part of the block scalar.
    while stream.column == indent && peek(stream.input) ≠ '\0'
        append!(chunks, breaks)
        leading_non_space = !is_s_white(peek(stream.input))
        length = 0
        while !in(peek(stream.input, length), "\0\r\n\u0085\u2028\u2029")
            length += 1
        end
        push!(chunks, prefix(stream.input, length))
        forwardchars!(stream, length)
        line_break = scan_line_break(YAMLV1_1(), stream)
        breaks, end_mark = scan_block_scalar_breaks(stream, indent)
        if stream.column == indent && peek(stream.input) != '\0'
            if folded && line_break == "\n" &&
               leading_non_space && !is_s_white(peek(stream.input))
                if isempty(breaks)
                    push!(chunks, ' ')
                end
            else
                push!(chunks, line_break)
            end
        else
            break
        end
    end

    # Chomp the tail.
    # Chomping may be Nothing or Bool.
    if chomping === nothing
        push!(chunks, line_break)
    elseif chomping
        push!(chunks, line_break)
        append!(chunks, breaks)
    end

    ScalarToken(Span(start_mark, end_mark), string(chunks...), false, style)
end


function scan_block_scalar_ignored_line(stream::TokenStream, start_mark::Mark)
    while peek(stream.input) == ' '
        forwardchars!(stream)
    end

    if peek(stream.input) == '#'
        while !in(peek(stream.input), "\0\r\n\u0085\u2028\u2029")
            forwardchars!(stream)
        end
    end

    if !in(peek(stream.input), "\0\r\n\u0085\u2028\u2029")
        throw(ScannerError("while scanning a block scalal", start_mark,
                           "expected a comment or a line break, but found '$(peek(stream.input))'",
                           get_mark(stream)))
    end

    scan_line_break(YAMLV1_1(), stream)
end


function scan_block_scalar_indicators(stream::TokenStream, start_mark::Mark)
    chomping = nothing
    increment = nothing
    c = peek(stream.input)
    if c == '+' || c == '-'
        chomping = c == '+'
        forwardchars!(stream)
        c = peek(stream.input)
        if isdigit(c)
            increment = parse(Int, c)
            increment == 0 && throw(ScannerError(
                "while scanning a block scalar", start_mark,
                "expected indentation indicator in the range 1-9, but found 0", get_mark(stream),
            ))
        end
    elseif isdigit(c)
        increment = parse(Int, c)
        increment == 0 && throw(ScannerError(
            "while scanning a block scalar", start_mark,
            "expected indentation indicator in the range 1-9, but found 0", get_mark(stream),
        ))
        forwardchars!(stream)
        c = peek(stream.input)
        if c == '+' || c == '-'
            chomping = c == '+'
            forwardchars!(stream)
        end
    end
    c = peek(stream.input)
    # c ∉ "\0 \r\n\u0085\u2028\u2029"
    !(c == '\0' || c == ' ' || c == '\r' || c == '\n' || c == '\u85' || c == '\u2028' || c == '\u2029') && throw(ScannerError(
        "while scanning a block scalar", start_mark,
        "expected chomping or indentation indicators, but found '$c'", get_mark(stream),
    ))
    chomping, increment
end


function scan_block_scalar_indentation(stream::TokenStream)
    chunks = Any[]
    max_indent = 0
    end_mark = get_mark(stream)
    while in(peek(stream.input), " \r\n\u0085\u2028\u2029")
        if peek(stream.input) != ' '
            push!(chunks, scan_line_break(YAMLV1_1(), stream))
            end_mark = get_mark(stream)
        else
            forwardchars!(stream)
            if stream.column > max_indent
                max_indent = stream.column
            end
        end
    end

    chunks, max_indent, end_mark
end


function scan_block_scalar_breaks(stream::TokenStream, indent)
    chunks = Any[]
    end_mark = get_mark(stream)
    while stream.column < indent && peek(stream.input) == ' '
        forwardchars!(stream)
    end

    while is_b_char(YAMLV1_1(), peek(stream.input))
        push!(chunks, scan_line_break(YAMLV1_1(), stream))
        end_mark = get_mark(stream)
        while stream.column < indent && peek(stream.input) == ' '
            forwardchars!(stream)
        end
    end

    chunks, end_mark
end


function scan_flow_scalar(stream::TokenStream, style::Char)
    double = style == '"'
    chunks = Any[]
    start_mark = get_mark(stream)
    q = peek(stream.input) # quote
    forwardchars!(stream)

    while peek(stream.input) != q || peek(stream.input, 1) == q
        append!(chunks, scan_flow_scalar_spaces(stream, double, start_mark))
        append!(chunks, scan_flow_scalar_non_spaces(stream, double, start_mark))
    end

    forwardchars!(stream)
    end_mark = get_mark(stream)
    ScalarToken(Span(start_mark, end_mark), string(chunks...), false, style)
end


const ESCAPE_REPLACEMENTS = Dict{Char,Char}(
    '0'  => '\0',
    'a'  => '\u0007',
    'b'  => '\u0008',
    't'  => '\u0009',
    '\t' => '\u0009',
    'n'  => '\u000a',
    'v'  => '\u000b',
    'f'  => '\u000c',
    'r'  => '\u000d',
    'e'  => '\u001b',
    ' '  => '\u0020',
    '"'  => '"',
    '\\' => '\\',
    'N'  => '\u0085',
    '_' => '\u00A0',
    'L'  => '\u2028',
    'P'  => '\u2029'
)


const ESCAPE_CODES = Dict{Char, Int}(
    'x' => 2,
    'u' => 4,
    'U' => 8
)


function scan_flow_scalar_non_spaces(stream::TokenStream, double::Bool,
                                     start_mark::Mark)
    chunks = Any[]
    while true
        length = 0
        while !in(peek(stream.input, length), "\'\"\\\0 \t\r\n\u0085\u2028\u2029")
            length += 1
        end
        if length > 0
            push!(chunks, prefix(stream.input, length))
            forwardchars!(stream, length)
        end

        c = peek(stream.input)
        if !double && c == '\'' && peek(stream.input, 1) == '\''
            push!(chunks, '\'')
            forwardchars!(stream, 2)
        elseif (double && c == '\'') || (!double && in(c, "\"\\"))
            push!(chunks, c)
            forward!(stream.input)
        elseif double && c == '\\'
            forward!(stream.input)
            c = peek(stream.input)
            if haskey(ESCAPE_REPLACEMENTS, c)
                push!(chunks, ESCAPE_REPLACEMENTS[c])
                forward!(stream.input)
            elseif haskey(ESCAPE_CODES, c)
                length = ESCAPE_CODES[c]
                forward!(stream.input)
                for k in 0:(length-1)
                    c = peek(stream.input, k)
                    if !in(peek(stream.input, k), "0123456789ABCDEFabcdef")
                        throw(ScannerError("while scanning a double-quoted scalar",
                                           start_mark,
                                           string("expected escape sequence of",
                                                  " $(length) hexadecimal",
                                                  "digits, but found '$(c)'"),
                                           get_mark(stream)))
                    end
                end
                push!(chunks, Char(parse(Int, prefix(stream.input, length), base = 16)))
                forwardchars!(stream, length)
            elseif is_b_char(YAMLV1_1(), c)
                scan_line_break(YAMLV1_1(), stream)
                append!(chunks, scan_flow_scalar_breaks(stream, double, start_mark))
            else
                throw(ScannerError("while scanning a double-quoted scalar",
                                   start_mark,
                                   "found unknown escape character '$(c)'",
                                   get_mark(stream)))
            end
        else
            return chunks
        end
    end
end


function scan_flow_scalar_spaces(stream::TokenStream, double::Bool,
                                 start_mark::Mark)
    chunks = Any[]
    length = 0
    while is_s_white(peek(stream.input, length))
        length += 1
    end
    whitespaces = prefix(stream.input, length)
    forwardchars!(stream, length)

    c = peek(stream.input)
    if c == '\0'
        throw(ScannerError("while scanning a quoted scalar", start_mark,
                           "found unexpected end of stream", get_mark(stream)))
    elseif is_b_char(YAMLV1_1(), c)
        line_break = scan_line_break(YAMLV1_1(), stream)
        breaks = scan_flow_scalar_breaks(stream, double, start_mark)
        if line_break != '\n'
            push!(chunks, line_break)
        else isempty(breaks)
            push!(chunks, ' ')
        end
        append!(chunks, breaks)
    else
        push!(chunks, whitespaces)
    end

    chunks
end


function scan_flow_scalar_breaks(stream::TokenStream, double::Bool,
                                 start_mark::Mark)
    chunks = Any[]
    while true
        pref = prefix(stream.input, 3)
        if pref == "---" || pref == "..." &&
           in(peek(stream.input, 3), "\0 \t\r\n\u0085\u2028\u2029")
            throw(ScannerError("while scanning a quoted scalar", start_mark,
                               "found unexpected document seperator",
                               get_mark(stream)))
        end

        while is_s_white(peek(stream.input))
            forward!(stream.input)
        end

        if is_b_char(YAMLV1_1(), peek(stream.input))
            push!(chunks, scan_line_break(YAMLV1_1(), stream))
        else
            return chunks
        end
    end
end


function scan_plain(stream::TokenStream)
    # See the specification for details.
    # We add an additional restriction for the flow context:
    #   plain scalars in the flow context cannot contain ',', ':' and '?'.
    # We also keep track of the `allow_simple_key` flag here.
    # Indentation rules are loosed for the flow context.
    chunks = Any[]
    start_mark = get_mark(stream)
    end_mark = start_mark
    indent = stream.indent + 1

    # We allow zero indentation for scalars, but then we need to check for
    # document separators at the beginning of the line.
    #if indent == 0:
    #    indent = 1
    spaces = Any[]
    while true
        length = 0
        if peek(stream.input) == '#'
            break
        end

        while true
            c = peek(stream.input, length)
            cnext = peek(stream.input, length + 1)
            if is_whitespace(YAMLV1_1(), c) ||
                c === nothing ||
                (stream.flow_level == 0 && c == ':' &&
                    (cnext === nothing || is_whitespace(YAMLV1_1(), cnext))) ||
                (stream.flow_level != 0 && in(c, ",:?[]{}"))
                break
            end
            length += 1
        end

        # It's not clear what we should do with ':' in the flow context.
        c = peek(stream.input)
        if stream.flow_level != 0 && c == ':' &&
            !in(peek(stream.input, length + 1), "\0 \t\r\n\u0085\u2028\u2029,[]{}")
            forwardchars!(stream, length)
            throw(ScannerError("while scanning a plain scalar", start_mark,
                               "found unexpected ':'", get_mark(stream)))
        end

        if length == 0
            break
        end

        stream.allow_simple_key = true
        append!(chunks, spaces)
        push!(chunks, prefix(stream.input, length))
        forwardchars!(stream, length)
        end_mark = get_mark(stream)
        spaces = scan_plain_spaces(stream, indent, start_mark)
        if isempty(spaces) || peek(stream.input) == '#' ||
            (stream.flow_level == 0 && stream.column < indent)
            break
        end
    end

    ScalarToken(Span(start_mark, end_mark), string(chunks...), true, nothing)
end


function scan_plain_spaces(stream::TokenStream, indent::Integer,
                           start_mark::Mark)
    chunks = Any[]
    length = 0
    while peek(stream.input, length) == ' '
        length += 1
    end

    whitespaces = prefix(stream.input, length)
    forwardchars!(stream, length)
    c = peek(stream.input)
    if is_b_char(YAMLV1_1(), c)
        line_break = scan_line_break(YAMLV1_1(), stream)
        stream.allow_simple_key = true
        if peek(stream.input) == '\uFEFF'
            return Any[]
        end
        pref = prefix(stream.input, 3)
        if pref == "---" || pref == "..." &&
            in(peek(stream.input, 3), "\0 \t\r\n\u0085\u2028\u2029")
            return Any[]
        end

        breaks = Any[]
        while in(peek(stream.input), " \r\n\u0085\u2028\u2029")
            if peek(stream.input) == ' '
                forwardchars!(stream)
            else
                push!(breaks, scan_line_break(YAMLV1_1(), stream))
                if peek(stream.input) == '\uFEFF'
                    return Any[]
                end
                pref = prefix(stream.input, 3)
                if pref == "---" || pref == "..." &&
                    in(peek(stream.input, 3), "\0 \t\r\n\u0085\u2028\u2029")
                    return Any[]
                end
            end
        end

        if line_break != '\n'
            push!(chunks, line_break)
        elseif isempty(breaks)
            push!(chunks, ' ')
        end
    elseif !isempty(whitespaces)
        push!(chunks, whitespaces)
    end

    chunks
end


function scan_tag_handle(stream::TokenStream, name::String, start_mark::Mark)
    c = peek(stream.input)
    if c != '!'
        throw(ScannerError("while scanning a $(name)", start_mark,
                           "expected '!', but found '$(c)'", get_mark(stream)))
    end
    length = 1
    c = peek(stream.input, length)
    if c != ' '
        while is_ns_ascii_letter(c) || isdigit(c) || c == '-' || c == '_'
            length += 1
            c = peek(stream.input, length)
        end

        if c != '!'
            forwardchars!(stream, length)
            throw(ScannerError("while scanning a $(name)", start_mark,
                               "expected '!', but found '$(c)'",
                               get_mark(stream)))
        end
        length += 1
    end

    value = prefix(stream.input, length)
    forwardchars!(stream, length)
    value
end


function scan_tag_uri(stream::TokenStream, name::String, start_mark::Mark)
    chunks = Any[]
    length = 0
    c = peek(stream.input, length)
    while is_ns_ascii_letter(c) || isdigit(c) || in(c, "-;/?:@&=+\$,_.!~*\'()[]%")
        if c == '%'
            push!(chunks, prefix(stream.input, length))
            forwardchars!(stream, length)
            length = 0
            push!(chunks, scan_uri_escapes(stream, name, start_mark))
        else
            length += 1
        end
        c = peek(stream.input, length)
    end

    if length > 0
        push!(chunks, prefix(stream.input, length))
        forwardchars!(stream, length)
        length = 0
    end

    if isempty(chunks)
        throw(ScannerError("while parsing a $(name)", start_mark,
                           "expected URI, but found '$(c)'",
                           get_mark(stream)))
    end

    string(chunks...)
end


function scan_uri_escapes(stream::TokenStream, name::String, start_mark::Mark)::String
    bytes = Char[]
    while peek(stream.input) == '%'
        forward!(stream.input)
        # check ns-hex-digit
        for k in 0:1
            c = peek(stream.input, k)
            is_ns_hex_digit(c) || throw(ScannerError(
                "while scanning a $name", start_mark,
                "expected URI escape sequence of 2 hexadecimal digits, but found '$c'", get_mark(stream),
            ))
        end
        push!(bytes, Char(parse(Int, prefix(stream.input, 2), base=16)))
        forwardchars!(stream, 2)
    end
    String(bytes)
end
