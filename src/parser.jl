
const DEFAULT_TAGS = Dict{String,String}("!" => "!", "!!" => "tag:yaml.org,2002:")


struct ParserError <: Exception
    context::Union{String, Nothing}
    context_mark::Union{Mark, Nothing}
    problem::Union{String, Nothing}
    problem_mark::Union{Mark, Nothing}
    note::Union{String, Nothing}

    function ParserError(context=nothing, context_mark=nothing,
                         problem=nothing, problem_mark=nothing,
                         note=nothing)
        new(context, context_mark, problem, problem_mark, note)
    end
end

function show(io::IO, error::ParserError)
    if error.context !== nothing
        print(io, error.context, " at ", error.context_mark, ": ")
    end
    print(io, error.problem, " at ", error.problem_mark)
end


mutable struct EventStream
    input::TokenStream
    next_event::Union{Event, Nothing}
    state::Union{Function, Nothing}
    states::Vector{Function}
    marks::Vector{Mark}
    yaml_version::Union{Tuple, Nothing}
    tag_handles::Dict{String, String}
    end_of_stream::Union{StreamEndEvent, Nothing}

    function EventStream(input::TokenStream)
        new(input, nothing, parse_stream_start, Function[], Mark[],
            nothing, Dict{String, String}(), nothing)
    end
end


function peek(stream::EventStream)
    version = YAMLV1_1()
    if stream.next_event === nothing
        if stream.state === nothing
            return nothing
        elseif stream.end_of_stream !== nothing
            stream.state = nothing
            return stream.end_of_stream
        else
            x = stream.state(version, stream)
            #@show x
            stream.next_event = x
            #stream.next_event = stream.state(version, stream)
        end
    end

    return stream.next_event
end


function forward!(stream::EventStream)
    version = YAMLV1_1()
    if stream.next_event === nothing
        if stream.state === nothing
            nothing
        elseif stream.end_of_stream !== nothing
            stream.state = nothing
            return stream.end_of_stream
        else
            stream.next_event = stream.state(version, stream)
        end
    end

    e = stream.next_event
    stream.next_event = nothing
    return e
end


function process_directives(version::YAMLVersion, stream::EventStream)
    stream.yaml_version = nothing
    stream.tag_handles = Dict{String, String}()
    while peek(version, stream.input) isa DirectiveToken
        token = forward!(version, stream.input)
        if token.name == "YAML"
            if stream.yaml_version !== nothing
                throw(ParserError(nothing, nothing,
                                  "found duplicate YAML directive",
                                  firstmark(token)))
            end
            major, minor = token.value
            if major != 1
                throw(ParserError(nothing, nothing,
                    "found incompatible YAML document (version 1.* is required)",
                    firstmark(token)))
            end
            # version =
            if minor == 0
                @warn "directive YAML 1.0 found but currently, YAML version 1.1 and 1.2 are supported. Fall back to 1.2."
                YAMLV1_2()
            elseif minor == 1
                YAMLV1_1()
            elseif minor == 2
                YAMLV1_2()
            else
                @warn "directive YAML 1.$minor found but currently, YAML version 1.1 and 1.2 are supported. Fall back to 1.2."
                YAMLV1_2()
            end
            stream.yaml_version = token.value
        elseif token.name == "TAG"
            handle, prefix = token.value
            if haskey(stream.tag_handles, handle)
                throw(ParserError(nothing, nothing,
                    "duplicate tag handle $(handle)", firstmark(token)))
            end
            stream.tag_handles[handle] = prefix
        end
    end

    if stream.tag_handles !== nothing
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

function parse_stream_start(version::YAMLVersion, stream::EventStream)
    token = forward!(version, stream.input) :: StreamStartToken
    event = StreamStartEvent(firstmark(token), lastmark(token),
                             token.encoding)
    stream.state = parse_implicit_document_start
    event
end


function parse_implicit_document_start(version::YAMLVersion, stream::EventStream)
    token = peek(version, stream.input)
    # Parse a byte order mark
    if token isa ByteOrderMarkToken
        forward!(version, stream.input)
        token = peek(version, stream.input)
    end
    if !(token isa Union{DirectiveToken, DocumentStartToken, StreamEndToken})
        stream.tag_handles = DEFAULT_TAGS
        event = DocumentStartEvent(firstmark(token), firstmark(token),
                                   false)

        push!(stream.states, parse_document_end)
        stream.state = parse_block_node

        event
    else
        parse_document_start(version, stream)
    end
end


function parse_document_start(version::YAMLVersion, stream::EventStream)
    # Parse any extra document end indicators.
    while peek(version, stream.input) isa DocumentEndToken
        stream.input = Iterators.rest(stream.input)
    end

    token = peek(version, stream.input)
    # Parse a byte order mark if it exists
    if token isa ByteOrderMarkToken
        forward!(version, stream.input)
        token = peek(version, stream.input)
    end

    # Parse explicit document.
    if !(token isa StreamEndToken)
        start_mark = firstmark(token)
        directive_version, tags = process_directives(version, stream)
        if !(peek(version, stream.input) isa DocumentStartToken)
            throw(ParserError(nothing, nothing,
                "expected '<document start>' but found $(typeof(token))"))
        end
        token = forward!(version, stream.input)
        event = DocumentStartEvent(start_mark, lastmark(token),
                                   true, directive_version, tags)
        push!(stream.states, parse_document_end)
        stream.state = parse_document_content
        event
    else
        # Parse the end of the stream
        token = forward!(version, stream.input)
        event = StreamEndEvent(firstmark(token), lastmark(token))
        @assert isempty(stream.states)
        @assert isempty(stream.marks)
        stream.state = nothing
        event
    end
end


function parse_document_end(version::YAMLVersion, stream::EventStream)
    token = peek(version, stream.input)
    start_mark = end_mark = firstmark(token)
    explicit = false
    if token isa DocumentEndToken
        forward!(version, stream.input)
        end_mark = lastmark(token)
        explicit = true
        stream.end_of_stream = StreamEndEvent(firstmark(token),
                                              lastmark(token))
    end
    event = DocumentEndEvent(start_mark, end_mark, explicit)
    stream.state = parse_document_start
    event
end


function parse_document_content(version::YAMLVersion, stream::EventStream)
    if peek(version, stream.input) isa Union{DirectiveToken, DocumentStartToken, DocumentEndToken, StreamEndToken}
        event = process_empty_scalar(stream, firstmark(peek(version, stream.input)))
        stream.state = pop!(stream.states)
        event
    else
        parse_block_node(version, stream)
    end
end


function parse_block_node(version::YAMLVersion, stream::EventStream)
    parse_node(version, stream, true)
end


function parse_flow_node(version::YAMLVersion, stream::EventStream)
    parse_node(version, stream)
end


function parse_block_node_or_indentless_sequence(version::YAMLVersion, stream::EventStream)
    parse_node(version, stream, true, true)
end


function _parse_node(version::YAMLVersion, token::AliasToken, stream::EventStream, block, indentless_sequence)
    forward!(version, stream.input)
    stream.state = pop!(stream.states)
    return AliasEvent(firstmark(token), lastmark(token), token.value)
end

function __parse_node(version::YAMLVersion, token::ScalarToken, stream::EventStream, block, start_mark, end_mark, anchor, tag, implicit)
    forward!(version, stream.input)
    end_mark = lastmark(token)
    if (token.plain && tag === nothing) || tag == "!"
        implicit = true, false
    elseif tag === nothing
        implicit = false, true
    else
        implicit = false, false
    end
    stream.state = pop!(stream.states)
    ScalarEvent(start_mark, end_mark, anchor, tag, implicit,
                        token.value, token.style)
end

function __parse_node(version::YAMLVersion, token::FlowSequenceStartToken, stream::EventStream, block, start_mark, end_mark, anchor, tag, implicit)
    end_mark = lastmark(token)
    stream.state = parse_flow_sequence_first_entry
    SequenceStartEvent(start_mark, end_mark, anchor, tag,
                               implicit, true)
end

function __parse_node(version::YAMLVersion, token::FlowMappingStartToken, stream::EventStream, block, start_mark, end_mark, anchor, tag, implicit)
    end_mark = lastmark(token)
    stream.state = parse_flow_mapping_first_key
    MappingStartEvent(start_mark, end_mark, anchor, tag,
                              implicit, true)
end

function __parse_node(version::YAMLVersion, token::BlockSequenceStartToken, stream::EventStream, block, start_mark, end_mark, anchor, tag, implicit)
    block || return nothing
    end_mark = firstmark(token)
    stream.state = parse_block_sequence_first_entry
    SequenceStartEvent(start_mark, end_mark, anchor, tag,
                               implicit, false)
end

function __parse_node(version::YAMLVersion, token::BlockMappingStartToken, stream::EventStream, block, start_mark, end_mark, anchor, tag, implicit)
    block || return nothing
    end_mark = firstmark(token)
    stream.state = parse_block_mapping_first_key
    MappingStartEvent(start_mark, end_mark, anchor, tag,
                              implicit, false)
end

function __parse_node(version::YAMLVersion, token, stream::EventStream, block, start_mark, end_mark, anchor, tag, implicit)
    if anchor !== nothing || tag !== nothing
        stream.state = pop!(stream.states)
        return ScalarEvent(start_mark, end_mark, anchor, tag,
                            (implicit, false), "", nothing)
    else
        node = block ? "block" : "flow"
        throw(ParserError("while parsing a $(node) node", start_mark,
                "expected the node content, but found $(typeof(token))",
                firstmark(token)))
    end
end

function _parse_node(version::YAMLVersion, token, stream::EventStream, block, indentless_sequence)
    anchor = nothing
    tag = nothing
    start_mark = end_mark = tag_mark = nothing
    if token isa AnchorToken
        forward!(version, stream.input)
        start_mark = firstmark(token)
        end_mark = lastmark(token)
        anchor = token.value
        token = peek(version, stream.input)
        if token isa TagToken
            forward!(version, stream.input)
            tag_mark = firstmark(token)
            end_mark = lastmark(token)
            tag = token.value
        end
    elseif token isa TagToken
        forward!(version, stream.input)
        start_mark = firstmark(token)
        end_mark = lastmark(token)
        tag = token.value
        token = peek(version, stream.input)
        if token isa AnchorToken
            forward!(version, stream.input)
            end_mark = lastmark(token)
            anchor = token.value
        end
    end

    if tag !== nothing
        handle, suffix = tag
        if handle !== nothing
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

    token = peek(version, stream.input)
    if start_mark === nothing
        start_mark = end_mark = firstmark(token)
    end

    event = nothing
    implicit = tag === nothing || tag == "!"
    if indentless_sequence && token isa BlockEntryToken
        end_mark = lastmark(token)
        stream.state = parse_indentless_sequence_entry
        event = SequenceStartEvent(start_mark, end_mark, anchor, tag, implicit,
                                   false)
    else
        event = __parse_node(version, token, stream, block, start_mark, end_mark, anchor, tag, implicit)
    end

    event
end

function parse_node(version::YAMLVersion, stream::EventStream, block=false, indentless_sequence=false)
    token = peek(version, stream.input)
    _parse_node(version, token, stream, block, indentless_sequence)
end

function parse_block_sequence_first_entry(version::YAMLVersion, stream::EventStream)
    token = forward!(version, stream.input)
    push!(stream.marks, firstmark(token))
    parse_block_sequence_entry(version, stream)
end


function parse_block_sequence_entry(version::YAMLVersion, stream::EventStream)
    token = peek(version, stream.input)
    if token isa BlockEntryToken
        forward!(version, stream.input)
        if !(peek(version, stream.input) isa Union{BlockEntryToken, BlockEndToken})
            push!(stream.states, parse_block_sequence_entry)
            return parse_block_node(version, stream)
        else
            stream.state = parse_block_sequence_entry
            return process_empty_scalar(stream, lastmark(token))
        end
    end

    if !(token isa BlockEndToken)
        throw(ParserError("while parsing a block collection", stream.marks[end],
                          "expected <block end>, but found $(typeof(token))",
                          firstmark(token)))
    end

    forward!(version, stream.input)
    pop!(stream.marks)
    stream.state = pop!(stream.states)
    SequenceEndEvent(firstmark(token), lastmark(token))
end


function parse_indentless_sequence_entry(version::YAMLVersion, stream::EventStream)
    token = peek(version, stream.input)
    if token isa BlockEntryToken
        forward!(version, stream.input)
        if !(peek(version, stream.input) isa Union{BlockEntryToken, KeyToken, ValueToken, BlockEndToken})
            push!(stream.states, parse_indentless_sequence_entry)
            return parse_block_node(version, stream)
        else
            stream.state = parse_indentless_sequence_entry
            return process_empty_scalar(stream, lastmark(token))
        end
    end

    stream.state = pop!(stream.states)
    SequenceEndEvent(firstmark(token), lastmark(token))
end


function parse_block_mapping_first_key(version::YAMLVersion, stream::EventStream)
    token = forward!(version, stream.input)
    push!(stream.marks, firstmark(token))
    parse_block_mapping_key(version, stream)
end


function parse_block_mapping_key(version::YAMLVersion, stream::EventStream)
    token = peek(version, stream.input)
    if token isa KeyToken
        forward!(version, stream.input)
        if !(peek(version, stream.input) isa Union{KeyToken, ValueToken, BlockEndToken})
            push!(stream.states, parse_block_mapping_value)
            return parse_block_node_or_indentless_sequence(version, stream)
        else
            stream.state = parse_block_mapping_value
            return process_empty_scalar(stream, lastmark(token))
        end
    end

    if !(token isa BlockEndToken)
        throw(ParserError("while parsing a block mapping", stream.marks[end],
                          "expected <block end>, but found $(typeof(token))",
                          firstmark(token)))
    end

    forward!(version, stream.input)
    pop!(stream.marks)
    stream.state = pop!(stream.states)
    MappingEndEvent(firstmark(token), lastmark(token))
end


function parse_block_mapping_value(version::YAMLVersion, stream::EventStream)
    token = peek(version, stream.input)
    if token isa ValueToken
        forward!(version, stream.input)
        if !(peek(version, stream.input) isa Union{KeyToken, ValueToken, BlockEndToken})
            push!(stream.states, parse_block_mapping_key)
            parse_block_node_or_indentless_sequence(version, stream)
        else
            stream.state = parse_block_mapping_key
            process_empty_scalar(stream, lastmark(token))
        end
    else
        stream.state = parse_block_mapping_key
        process_empty_scalar(stream, firstmark(token))
    end
end


function parse_flow_sequence_first_entry(version::YAMLVersion, stream::EventStream)
    token = forward!(version, stream.input)
    push!(stream.marks, firstmark(token))
    parse_flow_sequence_entry(version, stream, true)
end

function _parse_flow_sequence_entry(version::YAMLVersion, token::FlowSequenceEndToken, stream::EventStream, first_entry=false)
    forward!(version, stream.input)
    pop!(stream.marks)
    stream.state = pop!(stream.states)
    SequenceEndEvent(firstmark(token), lastmark(token))
end

function _parse_flow_sequence_entry(version::YAMLVersion, token::Any, stream::EventStream, first_entry=false)
    if !first_entry
        if token isa FlowEntryToken
            forward!(version, stream.input)
        else
            throw(ParserError("while parsing a flow sequence",
                              stream.marks[end],
                              "expected ',' or ']', but got $(typeof(token))",
                              firstmark(token)))
        end
    end

    token = peek(version, stream.input)
    if isa(token, KeyToken)
        stream.state = parse_flow_sequence_entry_mapping_key
        MappingStartEvent(firstmark(token), lastmark(token),
                          nothing, nothing, true, true)
    elseif isa(token, FlowSequenceEndToken)
        nothing
    else
        push!(stream.states, parse_flow_sequence_entry)
        parse_flow_node(version, stream)
    end
end

function parse_flow_sequence_entry(version::YAMLVersion, stream::EventStream, first_entry=false)
    token = peek(version, stream.input)
    _parse_flow_sequence_entry(version, token::Token, stream::EventStream, first_entry)
end

function parse_flow_sequence_entry_mapping_key(version::YAMLVersion, stream::EventStream)
    token = forward!(version, stream.input)
    if !(token isa Union{ValueToken, FlowEntryToken, FlowSequenceEndToken})
        push!(stream.states, parse_flow_sequence_entry_mapping_value)
        parse_flow_node(version, stream)
    else
        stream.state = parse_flow_sequence_entry_mapping_value
        process_empty_scalar(stream, lastmark(token))
    end
end


function parse_flow_sequence_entry_mapping_value(version::YAMLVersion, stream::EventStream)
    token = peek(version, stream.input)
    if token isa ValueToken
        forward!(version, stream.input)
        if !(peek(version, stream.input) isa Union{FlowEntryToken, FlowSequenceEndToken})
            push!(stream.states, parse_flow_sequence_entry_mapping_end)
            parse_flow_node(version, stream)
        else
            stream.state = parse_flow_sequence_entry_mapping_end
            process_empty_scalar(stream, lastmark(token))
        end
    else
        stream.state = parse_flow_sequence_entry_mapping_end
        process_empty_scalar(stream, firstmark(token))
    end
end


function parse_flow_sequence_entry_mapping_end(version::YAMLVersion, stream::EventStream)
    stream.state = parse_flow_sequence_entry
    token = peek(version, stream.input)
    MappingEndEvent(firstmark(token), lastmark(token))
end


function parse_flow_mapping_first_key(version::YAMLVersion, stream::EventStream)
    token = forward!(version, stream.input)
    push!(stream.marks, firstmark(token))
    parse_flow_mapping_key(version, stream, true)
end


function parse_flow_mapping_key(version::YAMLVersion, stream::EventStream, first_entry=false)
    token = peek(version, stream.input)
    if !(token isa FlowMappingEndToken)
        if !first_entry
            if token isa FlowEntryToken
                forward!(version, stream.input)
            else
                throw(ParserError("while parsing a flow mapping",
                                  stream.marks[end],
                                  "expected ',' or '}', but got $(typeof(token))",
                                  firstmark(token)))
            end
        end

        token = peek(version, stream.input)
        if token isa KeyToken
            forward!(version, stream.input)
            if !(peek(version, stream.input) isa Union{ValueToken, FlowEntryToken, FlowMappingEndToken})
                push!(stream.states, parse_flow_mapping_value)
                return parse_flow_node(version, stream)
            else
                stream.state = parse_flow_mapping_value
                return process_empty_scalar(stream, lastmark(token))
            end
        elseif !(token isa FlowMappingEndToken)
            push!(stream.states, parse_flow_mapping_empty_value)
            return parse_flow_node(version, stream)
        end
    end

    forward!(version, stream.input)
    pop!(stream.marks)
    stream.state = pop!(stream.states)
    MappingEndEvent(firstmark(token), lastmark(token))
end


function parse_flow_mapping_value(version::YAMLVersion, stream::EventStream)
    token = peek(version, stream.input)
    if token isa ValueToken
        forward!(version, stream.input)
        if !(peek(version, stream.input) isa Union{FlowEntryToken, FlowMappingEndToken})
            push!(stream.states, parse_flow_mapping_key)
            parse_flow_node(version, stream)
        else
            stream.state = parse_flow_mapping_key
            process_empty_scalar(stream, lastmark(token))
        end
    else
        stream.state = parse_flow_mapping_key
        process_empty_scalar(stream, firstmark(token))
    end
end


function parse_flow_mapping_empty_value(version::YAMLVersion, stream::EventStream)
    stream.state = parse_flow_mapping_key
    process_empty_scalar(stream, firstmark(peek(version, stream.input)))
end


function process_empty_scalar(stream::EventStream, mark::Mark)
    ScalarEvent(mark, mark, nothing, nothing, (true, false), "", nothing)
end



