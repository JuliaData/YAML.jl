
include("events.jl")

const DEFAULT_TAGS = @compat Dict{AbstractString,AbstractString}("!" => "!", "!!" => "tag:yaml.org,2002:")


immutable ParserError
    context::(@compat Union{AbstractString, Void})
    context_mark::(@compat Union{Mark, Void})
    problem::(@compat Union{AbstractString, Void})
    problem_mark::(@compat Union{Mark, Void})
    note::(@compat Union{AbstractString, Void})

    function ParserError(context=nothing, context_mark=nothing,
                         problem=nothing, problem_mark=nothing,
                         note=nothing)
        new(context, context_mark, problem, problem_mark, note)
    end
end

function show(io::IO, error::ParserError)
    if error.context != nothing
        print(io, error.context, " at ", error.context_mark, ": ")
    end
    print(io, error.problem, " at ", error.problem_mark)
end


type EventStream
    input::TokenStream
    next_event::(@compat Union{Event, Void})
    state::(@compat Union{Function, Void})
    states::Vector{Function}
    marks::Vector{Mark}
    yaml_version::(@compat Union{Tuple, Void})
    tag_handles::Dict{AbstractString, AbstractString}
    end_of_stream::(@compat Union{StreamEndEvent, Void})

    function EventStream(input::TokenStream)
        new(input, nothing, parse_stream_start, Function[], Mark[],
            nothing, Dict{AbstractString, AbstractString}(), nothing)
    end
end


function peek(stream::EventStream)
    if stream.next_event === nothing
        if stream.state === nothing
            return nothing
        elseif !is(stream.end_of_stream, nothing)
            stream.state = nothing
            return stream.end_of_stream
        else
            x = stream.state(stream)
            #@show x
            stream.next_event = x
            #stream.next_event = stream.state(stream)
        end
    end

    return stream.next_event
end


function forward!(stream::EventStream)
    if stream.next_event === nothing
        if stream.state === nothing
            nothing
        elseif !is(stream.end_of_stream, nothing)
            stream.state = nothing
            return stream.end_of_stream
        else
            stream.next_event = stream.state(stream)
        end
    end

    e = stream.next_event
    stream.next_event = nothing
    return e
end


function process_directives(stream::EventStream)
    stream.yaml_version = nothing
    stream.tag_handles = Dict{AbstractString, AbstractString}()
    while typeof(peek(stream.input)) == DirectiveToken
        token = forward!(stream.input)
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
        elseif token.name == "TAG"
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
    token = forward!(stream.input) :: StreamStartToken
    event = StreamStartEvent(token.span.start_mark, token.span.end_mark,
                             token.encoding)
    stream.state = parse_implicit_document_start
    event
end


function parse_implicit_document_start(stream::EventStream)
    token = peek(stream.input)
    if !in(typeof(token), [DirectiveToken, DocumentStartToken, StreamEndToken])
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
    while typeof(peek(stream.input)) == DocumentEndToken
        stream.input = rest(stream.input)
    end

    # Parse explicit document.
    token = peek(stream.input)
    if typeof(token) != StreamEndToken
        start_mark = token.span.start_mark
        version, tags = process_directives(stream)
        if typeof(peek(stream.input)) != DocumentStartToken
            throw(ParserError(nothing, nothing,
                "expected '<document start>' but found $(typeof(token))"))
        end
        token = forward!(stream.input)
        event = DocumentStartEvent(start_mark, token.span.end_mark,
                                   true, version, tags)
        push!(stream.states, parse_document_end)
        stream.state = parse_document_content
        event
    else
        # Parse the end of the stream
        token = forward!(stream.input)
        event = StreamEndEvent(token.span.start_mark, token.span.end_mark)
        @assert isempty(stream.states)
        @assert isempty(stream.marks)
        stream.state = nothing
        event
    end
end


function parse_document_end(stream::EventStream)
    token = peek(stream.input)
    start_mark = end_mark = token.span.start_mark
    explicit = false
    if typeof(token) == DocumentEndToken
        forward!(stream.input)
        end_mark = token.span.end_mark
        explicit = true
        stream.end_of_stream = StreamEndEvent(token.span.start_mark,
                                              token.span.end_mark)
    end
    event = DocumentEndEvent(start_mark, end_mark, explicit)
    stream.state = parse_document_start
    event
end


function parse_document_content(stream::EventStream)
    if in(peek(stream.input), [DirectiveToken, DocumentStartToken, DocumentEndToken,StreamEndToken])
        event = process_empty_scalar(stream, peek(stream.input).span.start_mark)
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
    token = peek(stream.input)
    if typeof(token) == AliasToken
        forward!(stream.input)
        stream.state = pop!(stream.states)
        return AliasEvent(token.span.start_mark, token.span.end_mark, token.value)
    end

    anchor = nothing
    tag = nothing
    start_mark = end_mark = tag_mark = nothing
    if typeof(token) == AnchorToken
        forward!(stream.input)
        start_mark = token.span.start_mark
        end_mark = token.span.end_mark
        anchor = token.value
        token = peek(stream.input)
        if typeof(token) == TagToken
            forward!(stream.input)
            tag_mark = token.span.start_mark
            end_mark = token.span.end_mark
            tag = token.value
        end
    elseif typeof(token) == TagToken
        forward!(stream.input)
        start_mark = token.span.start_mark
        end_mark = token.span.end_mark
        tag = token.value
        token = peek(stream.input)
        if typeof(token) == AnchorToken
            forward!(stream.input)
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

    token = peek(stream.input)
    if start_mark == nothing
        start_mark = end_mark = token.span.start_mark
    end

    event = nothing
    implicit = tag === nothing || tag == "!"
    if indentless_sequence && typeof(token) == BlockEntryToken
        end_mark = token.span.end_mark
        event = SequenceStartEvent(start_mark, end_mark, anchor, tag, implicit,
                                   false)
        stream.state = parse_indentless_sequence_entry
    else
        if typeof(token) == ScalarToken
            forward!(stream.input)
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
                    token.span.start_mark))
        end
    end

    event
end


function parse_block_sequence_first_entry(stream::EventStream)
    token = forward!(stream.input)
    push!(stream.marks, token.span.start_mark)
    parse_block_sequence_entry(stream)
end


function parse_block_sequence_entry(stream::EventStream)
    token = peek(stream.input)
    if typeof(token) == BlockEntryToken
        forward!(stream.input)
        if !in(typeof(peek(stream.input)), [BlockEntryToken, BlockEndToken])
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

    forward!(stream.input)
    pop!(stream.marks)
    stream.state = pop!(stream.states)
    SequenceEndEvent(token.span.start_mark, token.span.end_mark)
end


function parse_indentless_sequence_entry(stream::EventStream)
    token = peek(stream.input)
    if typeof(token) == BlockEntryToken
        forward!(stream.input)
        if !in(typeof(peek(stream.input)), [BlockEntryToken, KeyToken, ValueToken, BlockEndToken])
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
    token = forward!(stream.input)
    push!(stream.marks, token.span.start_mark)
    parse_block_mapping_key(stream)
end


function parse_block_mapping_key(stream::EventStream)
    token = peek(stream.input)
    if typeof(token) == KeyToken
        forward!(stream.input)
        if !in(typeof(peek(stream.input)), [KeyToken, ValueToken, BlockEndToken])
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

    forward!(stream.input)
    pop!(stream.marks)
    stream.state = pop!(stream.states)
    MappingEndEvent(token.span.start_mark, token.span.end_mark)
end


function parse_block_mapping_value(stream::EventStream)
    token = peek(stream.input)
    if typeof(token) == ValueToken
        forward!(stream.input)
        if !in(typeof(peek(stream.input)), [KeyToken, ValueToken, BlockEndToken])
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
    token = forward!(stream.input)
    push!(stream.marks, token.span.start_mark)
    parse_flow_sequence_entry(stream, first_entry=true)
end


function parse_flow_sequence_entry(stream::EventStream; first_entry=false)
    token = peek(stream.input)
    if typeof(token) != FlowSequenceEndToken
        if !first_entry
            if typeof(token) == FlowEntryToken
                forward!(stream.input)
            else
                throw(ParserError("while parsing a flow sequence",
                                  stream.mark[end],
                                  "expected ',' or ']', but got $(typeof(token))",
                                  token.span.start_mark))
            end
        end

        token = peek(stream.input)
        if typeof(token) == KeyToken
            stream.state = parse_flow_sequence_entry_mapping_key
            return MappingStartEvent(token.span.start_mark, token.span.end_mark,
                                     nothing, nothing, true, true)
        elseif typeof(token) != FlowSequenceEndToken
            push!(stream.states, parse_flow_sequence_entry)
            return parse_flow_node(stream)
        end
    end

    forward!(stream.input)
    pop!(stream.marks)
    stream.state = pop!(stream.states)
    SequenceEndEvent(token.span.start_mark, token.span.end_mark)
end


function parse_flow_sequence_entry_mapping_key(stream::EventStream)
    token = forward!(stream.input)
    if !in(typeof(token), [ValueToken, FlowEntryToken, FlowSequenceEndToken])
        push!(stream.states, parse_flow_sequence_entry_mapping_value)
        parse_flow_node(stream)
    else
        stream.state = parse_flow_sequence_entry_mapping_value
        process_empty_scalar(stream, token.span.end_mark)
    end
end


function parse_flow_sequence_entry_mapping_value(stream::EventStream)
    token = peek(stream.input)
    if typeof(token) == ValueToken
        forward!(stream.input)
        if !in(typeof(peek(stream.input)), [FlowEntryToken, FlowSequenceEndToken])
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
    token = peek(stream.input)
    MappingEndEvent(token.span.start_mark, token.span.end_mark)
end


function parse_flow_mapping_first_key(stream::EventStream)
    token = forward!(stream.input)
    push!(stream.marks, token.span.start_mark)
    parse_flow_mapping_key(stream, first_entry=true)
end


function parse_flow_mapping_key(stream::EventStream; first_entry=false)
    token = peek(stream.input)
    if typeof(token) != FlowMappingEndToken
        if !first_entry
            if typeof(token) == FlowEntryToken
                forward!(stream.input)
            else
                throw(ParserError("while parsing a flow mapping",
                                  stream.marks[end],
                                  "expected ',' or '}', but got $(typeof(token))",
                                  token.span.start_mark))
            end
        end

        token = peek(stream.input)
        if typeof(token) == KeyToken
            forward!(stream.input)
            if !in(typeof(peek(stream.input)), [ValueToken, FlowEntryToken, FlowMappingEndToken])
                push!(stream.states, parse_flow_mapping_value)
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

    forward!(stream.input)
    pop!(stream.marks)
    stream.state = pop!(stream.states)
    MappingEndEvent(token.span.start_mark, token.span.end_mark)
end


function parse_flow_mapping_value(stream::EventStream)
    token = peek(stream.input)
    if typeof(token) == ValueToken
        forward!(stream.input)
        if !in(typeof(peek(stream.input)), [FlowEntryToken, FlowMappingEndToken])
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
    process_empty_scalar(stream, peek(stream.input).span.start_mark)
end


function process_empty_scalar(stream::EventStream, mark::Mark)
    ScalarEvent(mark, mark, nothing, nothing, (true, false), "", nothing)
end



