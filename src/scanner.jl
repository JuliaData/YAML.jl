
include("queue.jl")

# Position within the document being parsed
immutable Mark
    index::Uint
    line::Uint
    column::Uint
end


# Where in the stream a particular token lies.
immutable Span
    start_mark::Mark
    end_mark::Mark
end


immutable SimpleKey
    token_number::Uint
    required::Bool
    mark::Mark
end


# Errors thrown by the scanner.
immutable ScannerError <: Exception
    context::Union(String, Nothing)
    context_mark::Union(Mark, Nothing)
    problem::String
    problem_mark::Mark
end


include("tokens.jl")


# A stream type for the scanner, which is just a IO stream with scanner state.
type TokenStream
    # Lazy sequence of Chars.
    chars

    # All tokens read.
    done::Bool

    # Tokens queued to be read.
    token_queue::Queue{Token}

    # Index of the start of the head of the stream. (0-based)
    index::Uint

    # Index of the current column. (0-based)
    column::Uint

    # Current line numebr. (0-based)
    line::Uint

    # Number of tokens read, not including those still in token_queue.
    tokens_taken::Uint

    # The number of unclosed '{' and '['. `flow_level == 0` means block
    # context.
    flow_level::Uint

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
    possible_simple_keys::Dict

    function TokenStream(stream::IO)
        tokstream = new(seq(stream), false, Queue{Token}(), 1, 0, 1, 0, 0, -1,
                        Array(Int,0), true, Dict())
        fetch_stream_start(tokstream)
        tokstream
    end
end


function get_mark(stream::TokenStream)
    Mark(stream.index, stream.line, stream.column)
end


# Peek the next i-th character. (0-based)
function peek(stream::TokenStream, i::Integer)
    ithchar = stream.chars
    for _ in 1:i
        if ithchar === nothing; return nothing; end
        ithchar = rest(ithchar)
    end
    if ithchar === nothing; return nothing; end
    first(ithchar)
end

peek(stream::TokenStream) = peek(stream, 0)


# Peek the string consisting of the next k characters.
function prefix(stream::TokenStream, k::Integer)
    pre = ""
    chars = stream.chars
    for _ in 1:k
        if chars === nothing; return nothing; end
        pre = string(pre, first(chars))
        chars = rest(chars)
    end
    pre
end

prefix(stream::TokenStream) = prefix(stream, 1)


# Advance the stream by k characters.
function forward(stream::TokenStream, k::Integer)
    for _ in 1:k
        c = first(stream.chars)
        stream.chars = rest(stream.chars)
        stream.index += 1
        if contains("\n\u0085\u2028\u2029", c) ||
            (c == '\r' && first(stream.chars) == '\n')
            stream.column = 0
            stream.line += 1
        else
            stream.column += 1
        end
    end
    stream.index += k
end

forward(stream::TokenStream) = forward(stream, 1)


function need_more_tokens(stream::TokenStream)
    if stream.done
        return false
    elseif isempty(stream.token_queue)
        return true
    end

    stale_possible_simple_keys(stream)
    next_possible_simple_key(stream) == stream.tokens_taken
end

# Return a lazy sequence of tokens given a input stream.
function tokenize(stream::TokenStream)
    token = next_token(stream)
    if token === nothing
        nothing
    else
        cons(token, @lazyseq tokenize(stream))
    end
end


# User-facing tokenize.
tokenize(stream::IO) = tokenize(TokenStream(stream))


# Return the next token in the stream.
#
# If there is not a well-formed token, throw a ScannerError. If the end of the
# input stream is reached, return nothing.
#
# Args:
#   stream (modified): A valid token stream.
#
# Returns:
#   An object deriving from Token or nothing.
#
function next_token(stream::TokenStream)
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

    c = peek(stream)
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
    elseif check_plain(stream)
        fetch_plain(stream)
    else
        # TODO: Throw a meaningful exception.
        throw(c)
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
    # restrictive then specification requires.
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

const whitespace = "\0 \t\r\n\u0085\u2028\u2029"


function check_directive(stream::TokenStream)
    stream.column == 0
end

function check_document_start(stream::TokenStream)
    stream.column == 0 &&
    prefix(stream, 3) == "---" &&
    contains(whitespace, peek(stream, 3))
end

function check_document_end(stream::TokenStream)
    stream.column == 0 &&
    prefix(stream, 3) == "..." &&
    (contains(whitespace, peek(stream, 3)) || peek(stream, 3) === nothing)
end

function check_block_entry(stream::TokenStream)
    contains(whitespace, peek(stream, 1))
end

function check_key(stream::TokenStream)
    stream.flow_level > 0 || contains(whitespace, peek(stream, 1))
end

function check_value(stream::TokenStream)
    stream.flow_level > 0 || contains(whitespace, peek(stream, 1))
end

function check_plain(stream::TokenStream)
    !contains("\0 \t\r\n\u0085\u2028\u2029-?:,[]{}#&*!|>\'\"%@`", peek(stream)) ||
    (!contains(whitespace, peek(stream, 1)) &&
     (peek(stream) == '-' || (stream.flow_level == 0 &&
                              contains("?:", peek(stream)))))
end


# Fetchers
# --------

function fetch_stream_start(stream::TokenStream)
    mark = get_mark(stream)
    # TODO: support other other encodings.
    enqueue!(stream.token_queue,
             StreamStartToken(Span(mark, mark), "utf-8"))
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


function fetch_document_indicator(stream::TokenStream, tokentype)
    # Set the current intendation to -1.
    unwind_indent(stream, -1)

    # Reset simple keys. Note that there could not be a block collection
    # after '---'.
    remove_possible_simple_key(stream)
    stream.allow_simple_key = false

    # Add DOCUMENT-START or DOCUMENT-END.
    start_mark = get_mark(stream)
    forward(stream, 3)
    end_mark = get_mark(stream)
    enqueue!(stream.token_queue, tokentype(Span(start_mark, end_mark)))
end


function fetch_flow_sequence_start(stream::TokenStream)
    fetch_flow_collection_start(stream, FlowSequenceStartToken)
end


function fetch_flow_mapping_start(stream::TokenStream)
    fetch_flow_collection_start(stream, FlowMappingStartToken)
end


function fetch_flow_collection_start(stream::TokenStream, tokentype)
    # '[' and '{' may start a simple key.
    save_possible_simple_key(stream)

    # Increase the flow level.
    stream.flow_level += 1
    
    # Simple keys are allowed after '[' and '{'.
    stream.allow_simple_key = true


    # Add FLOW-SEQUENCE-START or FLOW-MAPPING-START.
    start_mark = get_mark(stream)
    forward(stream)
    end_mark = get_mark(stream)
    enqueue!(stream.token_queue, tokentype(Span(start_mark, end_mark)))
end


function fetch_flow_sequence_end(stream::TokenStream)
    fetch_flow_collection_end(stream, FlowSequenceEndToken)
end


function fetch_flow_mapping_end(stream::TokenStream)
    fetch_flow_sequence_end(stream, FlowMappingEndToken)
end


function fetch_flow_collection_end(stream::TokenStream, tokentype)
    # Reset possible simple key on the current level.
    remove_possible_simple_key(stream)

    # Decrease the flow level.
    stream.flow_level -= 1

    # No simple keys after ']' or '}'.
    stream.allow_simple_key = false

    # Add FLOW-SEQUENCE-END or FLOW-MAPPING-END.
    start_mark = get_mark(stream)
    forward(stream)
    end_mark = get_mark(stream)
    enqueue!(stream.token_queue, tokentype(Span(start_mark, end_mark)))
end


function fetch_flow_entry(stream::TokenStream)
    # Simple keys are allowed after ','.
    stream.allow_simple_key = true

    # Reset possible simple key on the current level.
    remove_possible_simple_key(stream)

    # Add FLOW-ENTRY.
    start_mark = get_mark(stream)
    forward(stream)
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
    forward(stream)
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
            mork = get_mark(stream)
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
    forward(stream)
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
    forward(stream)
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
# Returns:
#   '\r\n'      :   '\n'
#   '\r'        :   '\n'
#   '\n'        :   '\n'
#   '\x85'      :   '\n'
#   '\u2028'    :   '\u2028'
#   '\u2029     :   '\u2029'
#   default     :   ''
#
function scan_line_break(stream::TokenStream)
    if contains("\r\n\u0085", peek(stream))
        if prefix(stream, 2) == "\r\n"
            forward(stream, 2)
        else
            forward(stream)
        end
        return "\n"
    elseif contains("\u2028\u2029", peek(stream))
        ch = peeek(stream)
        forward(stream)
        return ch
    end
    return ""
end


# Scan past whitespace to the next token.
function scan_to_next_token(stream::TokenStream)
    if stream.index == 0 && peek(stream) == '\uFEFF'
        forward(stream)
    end

    found = false
    while !found
        while peek(stream) == ' '
            forward(stream)
        end

        if peek(stream) == '#'
            forward(stream)
            while !contains("\0\r\n\u0085\u2028\u2029", peek(stream))
                forward(stream)
            end
        end

        if scan_line_break(stream) != ""
            if stream.flow_level == 0
                stream.allow_simple_key = true
            end
        else
            found = true
        end
    end
end


function scan_directive(stream::TokenStream)
    start_mark = get_mark(stream)
    forward(stream)
    name = scan_directive_name(stream, start_mark)

    value = nothing
    if name == "YAML"
        value = scan_yaml_directive_value(stream, start_mark)
        end_mark = get_mark(stream)
    elseif name == "TAG"
        value = scan_tag_directive_value(stream, start_mark)
        end_mark = get_mark(stream)
    else
        end_mark = get_mark(stream)
        while !contains("\0\r\n\u0085\u2028\u2029", peek(stream))
            forward(stream)
        end
    end

    scan_directive_ignored_line(stream, start_mark)
    DirectiveToken(Span(start_mark, end_mark), name, value)
end


function scan_directive_name(stream::TokenStream, start_mark::Mark)
    length = 0
    c = peek(stream)
    while isalnum(c) || c == '-' || c == '_'
        length += 1
        c = peek(stream, length)
    end

    if length == 0
        throw(ScannerError("while scanning a directive", start_mark,
                           "expected alphanumeric character, but found $(c)",
                           get_mark(stream)))
    end

    value = prefix(stream, length)
    forward(stream, length)

    c = peek(stream)
    if !contains("\0 \r\n\u0085\u2028\u2029", c)
        throw(ScannerError("while scanning a directive", start_mark,
                           "expected alphanumeric character, but bound $(c)",
                           get_mark(stream)))
    end

    value
end


function scan_yaml_directive_value(stream::TokenStream, start_mark::Mark)
    while peek(stream) == ' '
        forward(stream)
    end

    major = scan_yaml_directive_number(start_mark)
    if peek(stream) != '.'
        throw(ScannerError("while scanning a directive", start_mark,
                           "expected a digit or '.' but found $(peek(stream))",
                           get_mark(stream)))
    end
    forward(stream)
    minor = scan_yaml_directive_number(start_mark)
    if !contains("\0 \r\n\u0085\u2028\u2029", peek(stream))
        throw(ScannerError("while scanning a directive", start_mark,
                           "expected a digit or ' ', but found $(peek(stream))"))
    end
    return (major, minor)
end


function scan_yaml_directive_number(stream::TokenStream, start_mark::Mark)
    if !isdigit(peek(stream))
        throw(ScannerError("while scanning a directive", start_mark,
                           "expected a digit, but found $(peek(stream))"))
    end
    length = 0
    while isdigit(peek(length))
        length += 1
    end
    value = int(prefix(stream, length))
    forward(length)
    value
end


function scan_tag_directive_handle(stream::TokenStream, start_mark::Mark)
    value = scan_tag_handle(stream, "directive", start_mark)
    if peek(stream) != ' '
        throw(ScannerError("while scanning a directive", start_mark,
                           "expected ' ', but found $(peek(stream))",
                           get_mark(stream)))
    end
    value
end


function scan_tag_directive_prefix(stream::TokenStream, start_mark::Mark)
    value = scan_tag_uri(stream, "directive", start_mark)
    if !contains("\0 \r\n\u0085\u2028\u2029", peek(stream))
        throw(ScannerError("while scanning a directive", start_mark,
                           "expected ' ', but found $(peek(stream))",
                           get_mark(stream)))
    end
    value
end


function scan_directive_ignored_line(stream::TokenStream, start_mark::Mark)
    while peek(stream) == ' '
        forward(stream)
    end
    if peek(stream) == '#'
        forward(stream)
        while !contains("\0\r\n\u0085\u2028\u2029", peek(stream))
            forward(stream)
        end
    end
    if !contains("\0\r\n\u0085\u2028\u2029", peek(stream))
        throw(ScannerError("while scanning a directive", start_mark,
                           "expected a comment or a line break, but found $(peek(stream))",
                           get_mark(stream)))
     end 
     scan_line_break(stream)
end


function scan_anchor(stream::TokenStream, tokentype)
    start_mark = get_mark(stream)
    indicator = peek(stream)
    if indicator == '*'
        name = "alias"
    else
        name = "anchor"
    end
    forward(stream)
    length = 0
    c = peek(stream)
    while isalnum(c) || c == '-' || c == '_'
        length += 1
        c = peek(stream, length)
    end
    
    if length == 0
        throw(ScannerError("while scanning an $(name)", start_mark,
                           "expected an alphanumeric character, but found $(peek(stream))",
                           get_mark(stream)))
    end
    value = prefix(stream, length)
    forward(stream, length)
    if !contains("\0 \t\r\n\u0085\u2028\u2029?:,]}%@`", peek(stream))
        throw(ScannerError("while scanning an $(name)", start_mark,
                           "expected an alphanumeric character, but found $(peek(stream))",
                           get_mark(stream)))
    end
    end_mark = get_mark(stream)
    tokentype(Span(start_mark, end_mark), value)
end


function scan_tag(stream::TokenStream)
    start_mark = get_mark(stream)
    c = peek(stream)
    if c == '<'
        handle = nothing
        forward(stream, 2)
        suffix = scan_tag_uri(stream, "tag", start_mark)
        if peek(stream) != '>'
            throw(ScannerError("while parsing a tag", start_mark,
                               "expected '>', but found $(peek(stream))",
                               get_mark(stream)))
        end
        forward(stream)
    elseif contains("\0 \t\r\n\u0085\u2028\u2029", c) 
        handle = nothing
        suffix = '!'
        forward(stream)
    else
        length = 1
        use_handle = false
        while !contains("\0 \r\n\u0085\u2028\u2029", c)
            if c == '!'
                use_handle = true
                break
            end
            length += 1
            c = peek(stream, length)
        end
        handle = '!'
        if use_handle
            handle = scan_tag_handle(stream, "tag", start_mark)
        else
            handle = '!'
            forward(stream)
        end
        suffix = scan_tag_uri(stream, "tag", start_mark)
    end
    
    c = peek(stream)
    if !contains("\0 \r\n\u0085\u2028\u2029", c)
        throw(ScannerError("while scanning a tag", start_mark,
                           "expected ' ', but found $(c)",
                           get_mark(stream)))
    end
    
    value = (handle, suffix)
    end_mark = get_mark(stream)
    TagToken(Span(start_mark, end_mark), value)
end


function scan_block_scalar(stream::TokenStream, style::Char)
    folded = style == '>'
    
    chunks = {}
    start_mark = get_mark(stream)

    # Scan the header.
    forward(stream)
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
    while stream.column == indent && peek(stream) != '\0'
        append!(chunks, breaks)
        leading_non_space = peek(stream) != ' ' && peek(stream) != '\t'
        length = 0
        while !contains("\0\r\n\u0085\u2028\u2029", peek(stream, length))
            length += 1
        end
        push!(chunks, prefix(stream, length))
        forward(stream, length)
        line_break = scan_line_break(stream)
        breaks, end_mark = scan_block_scalar_breaks(stream, indent)
        if stream.column == indent && peek(stream) != '\0'
            if folded && line_break == '\n' &&
               leading_non_space && contains(" \t", peek(stream))
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
    if chomping != false
        push!(chunks, line_break)
    end
    if chomping == true
        append!(chunks, breaks)
    end

    ScalarToken(Span(start_mark, end_mark), string(chunks...), false, style)
end


function scan_block_scalar_ignored_line(stream::TokenStream, start_mark::Mark)
    while peek(stream) == ' '
        forward(stream)
    end

    if peek(stream) == '#'
        while !contains("\0\r\n\u0085\u2028\u2029", peek(stream))
            forward(stream)
        end
    end
    
    if !contains("\0\r\n\u0085\u2028\u2029", peek(stream))
        throw(ScannerError("while scanning a block scalal", start_mark,
                           "expected a commend or a line break, but found $(peek(stream))",
                           get_mark(stream)))
    end
    
    scan_line_break(stream)
end


function scan_block_scalar_indicators(stream::TokenStream, start_mark::Mark)
    chomping = nothing
    increment = nothing
    c = peek(stream)
    if c == '+' || c == '-'
        chomping = c == '+'
        forward(stream)
        c = peek(stream)
        if contains("0123456789", c)
            increment = int(string(c))
            if increment == 0
                throw(ScannerError("while scanning a block scalar", start_mark,
                    "expected indentation indicator in the range 1-9, but found 0",
                    get_mark(stream)))
            end
        end
    elseif contains("0123456789", c)
        increment = int(string(c))
        if increment == 0
            throw(ScannerError("while scanning a block scalar", start_mark,
                "expected indentation indicator in the range 1-9, but found 0",
                get_mark(stream)))
        end
        forward(stream)

        c = peek(stream)
        if c == '+' || c == '-'
            comping = c == '+'
            forward(stream)
        end
    end

    c = peek(stream)
    if !contains("\0 \r\n\u0085\u2028\u2029", c)
        throw(ScannerError("while scanning a block scalar", start_mark,
            "expected chomping or indentation indicators, but found $(c)",
            get_mark(stream)))
    end

    chomping, increment
end


function scan_block_scalar_indentation(stream::TokenStream)
    chunks = {}
    max_indent = 0
    end_mark = get_mark(stream)
    while contains(" \r\n\u0085\u2028\u2029", peek(stream))
        if peek(stream) != ' '
            push!(chunks, scan_line_break(stream))
            end_mark = get_mark(stream)
        else
            forward(stream)
            if stream.column > max_indent
                max_indent = stream.column
            end
        end
    end

    chunks, max_indent, end_mark
end


function scan_block_scalar_breaks(stream::TokenStream, indent)
    chunks = {}
    end_mark = get_mark(stream)
    while stream.column < indent && peek(stream) == ' '
        forward(stream)
    end

    while contains("\r\n\u0085\u2028\u2029", peek(stream))
        push!(chunks, scan_line_break(stream))
        end_mark = get_mark(stream)
        while stream.column < indent && peek(stream) == ' '
            forward(stream)
        end
    end

    chunks, end_mark
end


function scan_flow_scalar(stream::TokenStream, style::Char)
    double = style == '"'
    chunks = {}
    start_mark = get_mark(stream)
    q = peek(stream) # quote
    forward(stream)
    while peek(stream) != q
        append!(chunks, scan_flow_scalar_spaces(stream, double, start_mark))
        append!(chunks, scan_flow_scalar_non_spaces(stream, double, start_mark))
    end
    forward(stream)
    end_mark = get_mark(stream)
    ScalarToken(Span(start_mark, end_mark), string(chunks...), false, style)
end


const ESCAPE_REPLACEMENTS = {
    '0'  => '\0',
    'a'  => '\u0007',
    'b'  => '\u0008',
    't'  => '\u0009',
    '\t' => '\u0009',
    'n'  => '\u000a',
    'v'  => '\u000b',
    'f'  => '\u000c',
    'e'  => '\u001b',
    ' '  => '\u0020',
    '"'  => '"',
    '\\' => '\\',
    'N'  => '\u0085',
    'L'  => '\u2028',
    'P'  => '\u2029'
}


const ESCAPE_CODES = {
    'x' => 2,
    'u' => 4,
    'U' => 8
}


function scan_flow_scalar_non_spaces(stream::TokenStream, double::Bool,
                                     start_mark::Mark)
    chunks = {} 
    while true
        length = 0
        while !contains("\'\"\\\0 \t\r\n\u0085\u2028\u2029", peek(stream, length))
            length += 1
        end
        if length > 0
            push!(chunks, prefix(stream, length))
            forward(stream, length)
        end
        
        c = peek(stream)
        if !double && c == '\'' && peek(stream, 1) == '\''
            push!(chunks, '\'')
            forward(stream, 2)
        elseif (double && c == '\'') || (!double && contains("\"\\", c))
            push(chunks, c)
            forward(stream)
        elseif double && c == '\''
            forward(stream)
            c = peek(stream)
            if haskey(ESCAPE_REPLACEMENTS, c)
                push!(chunks, ESCAPE_REPLACEMENTS[c])
                forward(stream)
            elseif haskey(ESCAPE_CODES, c)
                length = ESCAPE_CODES[c]
                forward(stream)
                for k in 0:(length-1)
                    c = peek(stream, k)
                    if !contains("0123456789ABCDEFabcdef", peek(stream, k))
                        throw(ScannerError("while scanning a double-quoted scalar",
                                           start_mark,
                                           string("expected escape sequence of",
                                                  " $(length) hexadecimal",
                                                  "digits, but found $(c)"),
                                           get_mark(stream)))
                    end
                end
                push!(chunks, char(parse_hex(prefix(stream, length))))
                forward(stream, length)
            elseif contains("\r\n\u0085\u2028\u2029", c)
                scan_line_break(stream)
                append!(chunks, scan_flow_scalar_breaks(double, start_mark))
            else:
                throw(ScannerError("while scanning a double-quoted scalar",
                                   start_mark,
                                   "found unknown escape character $(c)",
                                   get_mark(stream)))
            end
        else
            return chunks
        end
    end
end


function scan_flow_scalar_spaces(stream::TokenStream, double::Bool,
                                 steart_mark::Mark)
    chunks = {} 
    length = 0
    while contains(" \t", peek(stream, length))
        length += 1
    end
    whitespaces = prefix(stream, length)
    forward(stream, length)
    
    c = peek(stream)
    if c == '\0'
        throw(ScannerError("while scanning a quoted scalar", start_mark,
                           "found unexpected end of stream", get_mark(stream)))
    elseif contains("\r\n\u0085\u2028\u2029", c)
        line_break = scan_line_break(stream)
        breaks = scan_flow_scalar_breaks(double, start_mark)
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
    chunks = {}                                 
    while true
        pref = prefix(stream, 3)
        if pref == "---" || pref == "..." &&
           contains("\0 \t\r\n\u0085\u2028\u2029", peek(stream, 3))
            throw(ScannerError("while scanning a quoted scalar", start_mark,
                               "found unexpected document seperator",
                               get_mark(stream)))
        end
        
        while contains(" \t", peek(stream))
            forward(stream)
        end
        
        if contains("\r\n\u0085\u2028\u2029", peek(stream))
            push(chunks, scan_line_break(stream))
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
    chunks = {}
    start_mark = get_mark(stream)
    end_mark = start_mark
    indent = stream.indent + 1

    # We allow zero indentation for scalars, but then we need to check for
    # document separators at the beginning of the line.
    #if indent == 0:
    #    indent = 1
    spaces = {}
    while true
        length = 0
        if peek(stream) == '#'
            break
        end

        while true
            c = peek(stream, length)
            if contains(whitespace, c) ||
                (stream.flow_level == 0 && c == ':' &&
                    contains(whitespace, peek(stream, length + 1))) ||
                (stream.flow_level != 0 && contains(",:?[]{}", c))
                break
            end
            length += 1
        end

        # It's not clear what we should do with ':' in the flow context.
        c = peek(stream)
        if stream.flow_level != 0 && c == ':' &&
            !contains("\0 \t\r\n\0u0085\u2028\u2029,[]{}", peek(stream, length + 1))
            forward(stream, length)
            throw(ScannerError("while scanning a plain scalar", start_mark,
                               "found unexpected ':'", get_mark(stream)))
        end

        if length == 0
            break
        end

        stream.allow_simple_key = true
        append!(chunks, spaces)
        push!(chunks, prefix(stream, length))
        forward(stream, length)
        end_mark = get_mark(stream)
        spaces = scan_plain_spaces(stream, indent, start_mark)
        if isempty(spaces) || peek(stream) == '#' ||
            (stream.flow_level == 0 && stream.column < indent)
            break
        end
    end

    ScalarToken(Span(start_mark, end_mark), string(chunks...), true, nothing)
end


function scan_plain_spaces(stream::TokenStream, indent::Integer,
                           start_mark::Mark)
    chunks = {}
    length = 0
    while peek(stream, length) == ' '
        length += 1
    end

    whitespaces = prefix(stream, length)
    forward(stream, length)
    c = peek(stream)
    if contains("\r\n\u0085\u2028\u2029", c)
        line_break = scan_line_break(stream)
        stream.allow_simple_key = true
        pref = prefix(stream, 3)
        if pref == "---" || pref == "..." &&
            contains("\0 \t\r\n\u0085\u2028\u2029", peek(stream, 3))
            return {}
        end

        breaks = {}
        while contains(" \r\n\u0085\u2028\u2029", peek(stream))
            if peek(stream) == ' '
                forward(stream)
            else
                push!(breaks, scan_line_break(stream))
                pref = prefix(stream, 3)
                if pref == "---" || pref == "..." &&
                    contains("\0 \t\r\n\u0085\u2028\u2029", peek(stream, 3))
                    return {}
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
    c = peek(stream)
    if c != '!'
        throw(ScannerError("while scanning a $(name)", start_mark,
                           "expected '!', but found $(c)", get_mark(stream)))
    end
    length = 1
    c = peek(stream, length)
    if c != ' '
        while isalnum(c) || c == '-' || c == '_'
            length += 1
            c = peek(stream, length)
        end
        
        if c != '!'
            forward(length)
            throw(ScannerError("while scanning a $(name)", start_mark,
                               "expected '!', but found $(c)",
                               get_mark(stream)()))
        end
        length += 1
    end
    
    value = prefix(stream, length)
    forward(stream, length)
    value
end


function scan_tag_uri(stream::TokenStream, start_mark::Mark)
    chunks = {}
    length = 0
    c = peek(stream, length)
    while isalnum(c) || contains("-;/?:@&=+\$,_.!~*\'()[]%", c)
        if c == '%'
            push!(chunks, prefix(stream, length))
            forward(stream, length)
            length = 0
            push!(chunks, scan_uri_escapes(stream, name, start_mark))
        else
            length += 1
        end
        c = peek(stream, length)
    end
        
    if length > 0
        push!(chunks, prefix(stream, length))
        forward(stream, length)
        length = 0
    end

    if isempty(chunks)
        throw(ScannerError("while parsing a $(name)", start_mark,
                           "expected URI, but found $(c)",
                           get_mark(stream)))
    end
    
    string(chunks...)
end


function scan_uri_escapes(stream::TokenStream, name::String, start_mark::Mark)
    bytes = {}
    mark = get_mark(stream)
    while peek(stream) == '%'
        forward(stream)
        for k in 0:1
            if !contains("0123456789ABCDEFabcdef", peek(stream, k))
                throw(ScannerError("while scanning a $(name)", start_mark,
                                   string("expected URI escape sequence of",
                                          " 2 hexadecimal digits, but found",
                                          " $(peek(stream, k))"),
                                   get_mark(stream)))
            end
        end
        push!(bytes, char(parse_hex(prefix(stream, 2))))
        forward(stream, 2)
    end
    
    string(bytes...)
end


