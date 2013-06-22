
include("events.jl")

const DEFAULT_TAGS = (String=>String)["!" => "!", "!!" => "tag:yaml.org,2002:"]


immutable ParserError
    context::Union(String, Nothing)
    context_mark::Union(Mark, Nothing)
    problem::Union(String, Nothing)
    problem_mark::Union(Mark, Nothing)
    note::Union(String, Nothing)

    function ParserError(context=nothing, context_mark=nothing,
                         problem=nothing, problem_mark=nothing,
                         note=nothing)
        new(context, context_mark, problem, problem_mark, note)
    end
end


type EventStream
    tokens
    state::Union(Function, Nothing)
    states::Vector{Function}
    marks::Vector{Mark}
    yaml_version::Union(Tuple, Nothing)
    tag_handles::Dict{String, String}

    function EventStream(tokens)
        new(tokens, parse_stream_start, Function[], Mark[],
            nothing, Dict{String, String}())
    end
end


# Return a lazy sequence of parser events.
parse(input::IO) = parse(EventStream(tokenize(input)))

function parse(stream::EventStream)
    event = next_event(stream)
    if event === nothing
        nothing
    else
        cons(event, @lazyseq parse(stream))
    end
end


# Return the next token, and advance the token stream.
function pop_token(stream::EventStream)
    token = first(stream.tokens)
    stream.tokens = rest(stream.tokens)
    token
end


# Return the next event in the event stream, or nothing if finished.
function next_event(stream::EventStream)
    stream.state === nothing ? nothing : stream.state(stream)
end


function process_directives(stream::EventStream)
    stream.yaml_version = nothing
    stream.tag_handles = Dict{String, String}()
    while typeof(first(stream.tokens)) == DirectiveToken
        token = pop_token(stream)
        if token.name == "YAML"
            if !is(stream.yaml_version, nothing)
                throw(ParserError(nothing, nothing,
                                  "found duplicate YAML directive",
                                  token.start_mark))
            end
            major, minor = token.value
            if major != 1
                throw(ParserError(nothing, nothing,
                    "found incompatible YAML document (version 1.* is required)",
                    token.start_mark))
            end
            stream.yaml_version = token.value
        elseif taken.name == "TAG"
            handle, prefix = token.value
            if haskey(stream.tag_handles, handle)
                throw(ParserError(nothing, nothing,
                    "duplicate tag handle $(handle)", token.start_mark))
            end
            stream.tag_handles[handle] = prefix
        end
    end

    if !is(stream.tag_handles, nothing)
        value = stream.yaml_version, copy(stream.tag_handles)
    else
        value = stream.yaml_version, nothing
    end

    for key in keys(DEFAULT_TAGS)
        if !haskey(stream.tag_handles, key)
            stream.tag_handles[key] = DEFAULT_TAGS[key]
        end
    end

    value
end


# Parser state functions

function parse_stream_start(stream::EventStream)
    token = pop_token(stream) :: StreamStartToken
    event = StreamStartEvent(token.span.start_mark, token.span.end_mark,
                             token.encoding)
    stream.state = parse_implicit_document_start
    event
end


function parse_implicit_document_start(stream::EventStream)
    token = first(stream.tokens)
    if !contains([DirectiveToken, DocumentStartToken, StreamEndToken],
                typeof(token))
        stream.tag_handles = DEFAULT_TAGS
        event = DocumentStartEvent(token.span.start_mark, token.span.start_mark,
                                   false)

        push!(stream.states, parse_document_end)
        stream.state = parse_block_node

        event
    else
        parse_document_start(stream)
    end
end


function parse_document_start(stream::EventStream)
    # Parse any extra document end indicators.
    while typeof(first(stream.tokens)) == DocumentEndToken
        stream.tokens = rest(stream.tokens)
    end

    # Parse explicit document.
    token = first(stream.tokens)
    if typeof(token) != StreamEndToken
        start_mark = token.span.start_mark
        version, tags = process_directives(stream)
        if typeof(first(stream.tokens)) != DocumentStartToken
            throw(ParserError(nothing, nothing,
                "expected '<document start>' but found $(typeof(token))"))
        end
        token = pop_token(stream)
        event = DocumentStartEvent(start_mark, token.span.end_mark,
                                   true, version, tags)
        push!(stream.states, parse_document_end)
        stream.state = parse_document_content
        event
    else
        # Parse the end of the stream
        token = pop_token(stream)
        event = StreamEndEvent(token.span.start_mark, token.span.end_mark)
        @assert isempty(stream.states)
        @assert isempty(stream.marks)
        stream.state = nothing
        event
    end
end


function parse_document_end(stream::EventStream)
    token = first(stream.tokens)
    start_mark = end_mark = token.span.start_mark
    explicit = false
    if typeof(token) == DocumentEndToken
        pop_token(stream)
        end_mark = token.end_mark
        explicit = true
    end
    event = DocumentEndEvent(start_mark, end_mark, explicit)
    stream.state = parse_document_start
    event
end


function parse_document_content(stream::EventStream)
    if contains([DirectiveToken, DocumentStartToken, DocumentEndToken,
                 StreamEndToken], first(stream.tokens))
        event = process_empty_scalar(stream, first(stream.tokens).span.start_mark)
        stream.state = pop!(stream.states)
        event
    else
        parse_block_node(stream)
    end
end


function parse_block_node(stream::EventStream)
    parse_node(stream, block=true)
end


function parse_flow_node(stream::EventStream)
    parse_node(stream)
end


function parse_block_node_or_indentless_sequence(stream::EventStream)
    parse_node(stream, block=true, indentless_sequence=true)
end


function parse_node(stream::EventStream; block=false, indentless_sequence=false)
    token = first(stream.tokens)
    if typeof(token) == AliasToken
        pop_token(stream)
        stream.state = pop!(stream.states)
        AliasEvent(token.span.start_mark, token.span.end_mark, token.value)
    end

    anchor = nothing
    tag = nothing
    start_mark = end_mark = tag_mark = nothing
    if typeof(token) == AnchorToken
        pop_token(stream)
        start_mark = token.span.start_mark
        end_mark = token.span.end_mark
        anchor = token.value
        token = first(stream.tokens)
        if typeof(token) == TagToken
            pop_token(stream)
            tag_mark = token.span.start_mark
            end_mark = token.span.end_mark
            tag = token.value
        end
    elseif typeof(token) == TagToken
        pop_token(stream)
        start_mark = token.span.start_mark
        end_mark = token.span.end_mark
        tag = token.value
        token = first(stream.tokens)
        if typeof(token) == AnchorToken
            pop_token(stream)
            end_mark = token.end_mark
            anchor = token.value
        end
    end

    if !is(tag, nothing)
        handle, suffix = tag
        if !is(handle, nothing)
            if !haskey(stream.tag_handles, handle)
                throw(ParserError("while parsing a node", start_mark,
                                  "found undefined tag handle $(handle)",
                                  tag_mark))
            end
            tag = string(stream.tag_handles[handle], suffix)
        else
            tag = suffix
        end
    end

    token = first(stream.tokens)
    if start_mark == nothing
        start_mark = end_mark = token.span.start_mark
    end

    event = nothing
    implicit = tag === nothing || tag == "!"
    if indentless_sequence && typeof(token) == BlockEntryToken
        end_mark = stream.span.end_mark
        event = SequenceStartEvent(start_mark, end_mark, anchor, tag, implicit)
        stream.state = parse_indentless_sequence_entry
    else
        if typeof(token) == ScalarToken
            pop_token(stream)
            end_mark = token.span.end_mark
            if (token.plain && tag == nothing) || tag == "!"
                implicit = true, false
            elseif tag == nothing
                implicit = false, true
            else
                implicit = false, false
            end
            event = ScalarEvent(start_mark, end_mark, anchor, tag, implicit,
                                token.value, token.style)
            stream.state = pop!(stream.states)
        elseif typeof(token) == FlowSequenceStartToken
            end_mark = token.span.end_mark
            event = SequenceStartEvent(start_mark, end_mark, anchor, tag,
                                       implicit, true)
            stream.state = parse_flow_sequence_first_entry
        elseif typeof(token) == FlowMappingStartToken
            end_mark = token.span.end_mark
            event = MappingStartEvent(start_mark, end_mark, anchor, tag,
                                      implicit, true)
            stream.state = parse_flow_mapping_first_key
        elseif block && typeof(token) == BlockSequenceStartToken
            end_mark = token.span.start_mark
            event = SequenceStartEvent(start_mark, end_mark, anchor, tag,
                                       implicit, false)
            stream.state = parse_block_sequence_first_entry
        elseif block && typeof(token) == BlockMappingStartToken
            end_mark = token.span.start_mark
            event = MappingStartEvent(start_mark, end_mark, anchor, tag,
                                      implicit, false)
            stream.state = parse_block_mapping_first_key
        elseif !is(anchor, nothing) || !is(tag, nothing)
            event = ScalarEvent(start_mark, end_mark, anchor, tag,
                                (implicit, false), "")
            stream.state = pop!(stream.states)
        else
            node = block ? "block" : "flow"
            throw(ParserError("while parsing a $(node) node", start_mark,
                    "expected the node content, but found $(typeof(token))",
                    token.start_mark))
        end
    end

    event
end


function parse_block_sequence_first_entry(stream::EventStream)
    token = pop_token(stream)
    push!(stream.marks, token.span.start_mark)
    parse_block_sequence_entry(stream)
end


function parse_block_sequence_entry(stream::EventStream)
    token = first(stream.tokens)
    if typeof(token) == BlockEntryToken
        pop_token(stream)
        if !contains([BlockEntryToken, BlockEndToken], typeof(first(stream.tokens)))
            push!(stream.states, parse_block_sequence_entry)
            return parse_block_node(stream)
        else
            stream.state = parse_block_sequence_entry
            return process_empty_scalar(stream, token.span.end_mark)
        end
    end

    if typeof(token) != BlockEndToken
        throw(ParserError("while parsing a block collection", stream.marks[end],
                          "expected <block end>, but found $(typeof(token))",
                          token.span.start_mark))
    end

    pop_token(stream)
    pop!(stream.marks)
    stream.state = pop!(stream.states)
    SequenceEndEvent(token.span.start_mark, token.span.end_mark)
end


function parse_indentless_sequence_entry(stream::EventStream)
    token = first(stream.tokens)
    if typeof(token) == BlockEntryToken
        pop_token(stream)
        if !contains([BlockEntryToken, KeyToken, ValueToken, BlockEndToken],
                     typeof(first(stream.tokens)))
            push!(stream.states, parse_indentless_sequence_entry)
            return parse_block_node(stream)
        else
            stream.state = parse_indentless_sequence_entry
            return process_empty_scalar(stream, token.end_mark)
        end
    end

    stream.state = pop!(stream.states)
    SequenceEndEvent(token.span.start_mark, token.span.end_mark)
end


function parse_block_mapping_first_key(stream::EventStream)
    token = pop_token(stream)
    push!(stream.marks, token.span.start_mark)
    parse_block_mapping_key(stream)
end


function parse_block_mapping_key(stream::EventStream)
    token = first(stream.tokens)
    if typeof(token) == KeyToken
        pop_token(stream)
        if !contains([KeyToken, ValueToken, BlockEndToken],
                     typeof(first(stream.tokens)))
            push!(stream.states, parse_block_mapping_value)
            return parse_block_node_or_indentless_sequence(stream)
        else
            stream.state = parse_block_mapping_value
            return process_empty_scalar(stream, token.span.end_mark)
        end
    end

    if typeof(token) != BlockEndToken
        throw(ParserError("while parsing a block mapping", stream.marks[end],
                          "expected <block end>, but found $(typeof(token))",
                          token.span.start_mark))
    end

    pop_token(stream)
    pop!(stream.marks)
    stream.state = pop!(stream.states)
    MappingEndEvent(token.span.start_mark, token.span.end_mark)
end


function parse_block_mapping_value(stream::EventStream)
    token = first(stream.tokens)
    if typeof(token) == ValueToken
        pop_token(stream)
        if !contains([KeyToken, ValueToken, BlockEndToken],
                     typeof(first(stream.tokens)))
            push!(stream.states, parse_block_mapping_key)
            parse_block_node_or_indentless_sequence(stream)
        else
            stream.state = parse_block_mapping_key
            process_empty_scalar(stream, token.span.end_mark)
        end
    else
        stream.state = parse_block_mapping_key
        process_empty_scalar(stream, token.span.start_mark)
    end
end


function parse_flow_sequence_first_entry(stream::EventStream)
    token = pop_token(stream)
    push!(stream.marks, token.span.start_mark)
    parse_flow_sequence_entry(stream, first_entry=true)
end


function parse_flow_sequence_entry(stream::EventStream; first_entry=false)
    token = first(stream.tokens)
    if typeof(token) != FlowSequenceEndToken
        if !first_entry
            if typeof(token) == FlowEntryToken
                pop_token(stream)
            else
                throw(ParserError("while parsing a flow sequence",
                                  stream.marsk[end],
                                  "expected ',' or ']', but got $(typeof(token))",
                                  token.span.start_mark))
            end
        end

        token = first(stream.tokens)
        if typeof(token) == KeyToken
            stream.state = parse_flow_sequence_entry_mapping_key
            return MappingStartEvent(token.span.start_mark, token.span.end_mark,
                                     nothing, nothing, true, true)
        elseif typeof(token) != FlowSequenceEndToken
            push!(stream.states, parse_flow_sequence_entry)
            return parse_flow_node(stream)
        end
    end

    pop_token(stream)
    pop!(stream.marks)
    stream.state = pop!(stream.states)
    SequenceEndEvent(token.span.start_mark, token.span.end_mark)
end


function parse_flow_sequence_entry_mapping_key(stream::EventStream)
    token = pop_token(stream)
    if !contains([ValueToken, FlowEntryToken, FlowSequenceEndToken],
                 typeof(token))
        push!(stream.states, parse_flow_sequence_entry_mapping_value)
        parse_flow_node(stream)
    else
        stream.state = parse_flow_sequence_entry_mapping_value
        process_empty_scalar(stream, token.span.end_mark)
    end
end


function parse_flow_sequence_entry_mapping_value(stream::EventStream)
    token = first(stream.tokens)
    if typeof(token) == ValueToken
        pop_token(stream)
        if !contains([FlowEntryToken, FlowSequenceEndToken],
                     typeof(first(stream.tokens)))
            push!(stream.states, parse_flow_sequence_entry_mapping_end)
            parse_flow_node(stream)
        else
            stream.state = parse_flow_sequence_entry_mapping_end
            process_empty_scalar(stream, token.span.end_mark)
        end
    else
        stream.state = parse_flow_sequence_entry_mapping_end
        process_empty_scalar(stream, token.span.start_mark)
    end
end


function parse_flow_sequence_entry_mapping_end(stream::EventStream)
    stream.state = parse_flow_sequence_entry
    token = first(stream.tokens)
    MappingEndEvent(token.span.start_mark, token.span.end_mark)
end


function parse_flow_mapping_first_key(stream::EventStream)
    token = pop_token(stream)
    push!(stream.marks, token.span.start_mark)
    parse_flow_mapping_key(stream, first_entry=true)
end


function parse_flow_mapping_key(stream::EventStream; first_entry=false)
    token = first(stream.tokens)
    if typeof(token) != FlowMappingEndToken
        if !first_entry
            if typeof(token) == FlowEntryToken
                pop_token(stream)
            else
                throw(ParserError("while parsing a flow mapping",
                                  stream.marks[end],
                                  "expected ',' or '}', but got $(typeof(token))",
                                  token.span.start_mark))
            end
        end

        token = first(stream.tokens)
        if typeof(token) == KeyToken
            pop_token(stream)
            if !contains([ValueToken, FlowEntryToken, FlowMappingEndToken],
                         typeof(first(stream.tokens)))
                push!(stream.states, parse-flow_mapping_value)
                return parse_flow_node(stream)
            else
                stream.state = parse_flow_mapping_value
                return process_empty_scalar(stream, token.span.end_mark)
            end
        elseif typeof(token) != FlowMappingEndToken
            push!(stream.states, parse_flow_mapping_empty_value)
            return parse_flow_node(stream)
        end
    end

    pop_token(stream)
    pop!(stream.marks)
    stream.state = pop!(stream.states)
    MappingEndEvent(token.span.start_mark, token.span.end_mark)
end


function parse_flow_mapping_value(stream::EventStream)
    token = first(stream.tokens)
    if typeof(token) == ValueToken
        pop_token(stream)
        if !contains([FlowEntryToken, FlowMappingEndToken],
                     typeof(first(stream.tokens)))
            push!(stream.states, parse_flow_mapping_key)
            parse_flow_node(stream)
        else
            stream.state = parse_flow_mapping_key
            process_empty_scalar(stream, token.span.end_mark)
        end
    else
        stream.state = parse_flow_mapping_key
        process_empty_scalar(stream, token.span.start_mark)
    end
end


function parse_flow_mapping_empty_value(stream::EventStream)
    stream.state = parse_flow_mapping_key
    process_empty_scalar(stream, first(stream.tokens).span.start_mark)
end


function process_empty_scalar(stream::EventStream, mark::Mark)
    ScalarEvent(mork, mark, nothing, nothing, (true, false), "")
end



