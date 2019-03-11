
include("nodes.jl")
include("resolver.jl")


struct ComposerError
    context::Union{String, Nothing}
    context_mark::Union{Mark, Nothing}
    problem::Union{String, Nothing}
    problem_mark::Union{Mark, Nothing}
    note::Union{String, Nothing}

    function ComposerError(context=nothing, context_mark=nothing,
                           problem=nothing, problem_mark=nothing,
                           note=nothing)
        new(context, context_mark, problem, problem_mark, note)
    end
end

function show(io::IO, error::ComposerError)
    if error.context != nothing
        print(io, error.context, " at ", error.context_mark, ": ")
    end
    print(io, error.problem, " at ", error.problem_mark)
end


mutable struct Composer
    input::EventStream
    anchors::Dict{String, Node}
    resolver::Resolver
end


function compose(events)
    composer = Composer(events, Dict{String, Node}(), Resolver())
    @assert typeof(forward!(composer.input)) == StreamStartEvent
    node = compose_document(composer)
    if typeof(peek(composer.input)) == StreamEndEvent
        forward!(composer.input)
    else
        @assert typeof(peek(composer.input)) == DocumentStartEvent
    end
    node
end


function compose_document(composer::Composer)
    @assert typeof(forward!(composer.input)) == DocumentStartEvent
    node = compose_node(composer)
    @assert typeof(forward!(composer.input)) == DocumentEndEvent
    empty!(composer.anchors)
    node
end


function handle_event(event::AliasEvent, composer)
    anchor = event.anchor
    forward!(composer.input)
    haskey(composer.anchors, anchor) || throw(ComposerError(
            nothing, nothing, "found undefined alias '$(anchor)'", event.start_mark))
    return composer.anchors[anchor]
end

handle_error(event, composer, anchor) =
    anchor !== nothing && haskey(composer.anchors, anchor) && throw(ComposerError(
                "found duplicate anchor '$(anchor)'; first occurance",
                composer.anchors[anchor].start_mark, "second occurence",
                event.start_mark))

function handle_event(event::ScalarEvent, composer)
    anchor = event.anchor
    handle_error(event, composer, anchor)
    compose_scalar_node(composer, anchor)
end

function handle_event(event::SequenceStartEvent, composer)
    anchor = event.anchor
    handle_error(event, composer, anchor)
    compose_sequence_node(composer, anchor)
end

function handle_event(event::MappingStartEvent, composer)
    anchor = event.anchor
    handle_error(event, composer, anchor)
    compose_mapping_node(composer, anchor)
end

handle_event(event, composer) = nothing


function compose_node(composer::Composer)
    event = peek(composer.input)
    handle_event(event, composer)
end


function _compose_scalar_node(event::ScalarEvent, composer::Composer, anchor::Union{String, Nothing})
    tag = event.tag
    if tag === nothing || tag == "!"
        tag = resolve(composer.resolver, ScalarNode,
                      event.value, event.implicit)
    end

    node = ScalarNode(tag, event.value, event.start_mark, event.end_mark,
                      event.style)
    if anchor !== nothing
        composer.anchors[anchor] = node
    end

    node
end

compose_scalar_node(composer::Composer, anchor::Union{String, Nothing}) =
    _compose_scalar_node(forward!(composer.input), composer, anchor)


__compose_sequence_node(event::SequenceEndEvent, composer, node) = false
function __compose_sequence_node(event::Event, composer, node)
    push!(node.value, compose_node(composer))
    true
end

function _compose_sequence_node(start_event::SequenceStartEvent, composer, anchor)
    tag = start_event.tag
    if tag === nothing || tag == "!"
        tag = resolve(composer.resolver, SequenceNode,
                      nothing, start_event.implicit)
    end

    node = SequenceNode(tag, Any[], start_event.start_mark, nothing,
                        start_event.flow_style)
    if anchor !== nothing
        composer.anchors[anchor] = node
    end

    while true
        event = peek(composer.input)
        __compose_sequence_node(event, composer, node) || break
    end

    end_event = forward!(composer.input)
    node.end_mark = end_event.end_mark

    node
end

compose_sequence_node(composer::Composer, anchor::Union{String, Nothing}) =
    _compose_sequence_node(forward!(composer.input), composer, anchor)


__compose_mapping_node(event::MappingEndEvent, composer, node) = false
function __compose_mapping_node(event::Event, composer, node)
    item_key = compose_node(composer)
    item_value = compose_node(composer)
    push!(node.value, (item_key, item_value))
    true
end

function _compose_mapping_node(start_event::MappingStartEvent, composer::Composer, anchor::Union{String, Nothing})
    tag = start_event.tag
    if tag === nothing || tag == "!"
        tag = resolve(composer.resolver, MappingNode,
                      nothing, start_event.implicit)
    end

    node = MappingNode(tag, Any[], start_event.start_mark, nothing,
                       start_event.flow_style)
    if anchor !== nothing
        composer.anchors[anchor] = node
    end

    while true
        event = peek(composer.input)
        __compose_mapping_node(event, composer, node) || break
    end

    end_event = forward!(composer.input)
    node.end_mark = end_event.end_mark

    node
end

compose_mapping_node(composer::Composer, anchor::Union{String, Nothing}) =
    _compose_mapping_node(forward!(composer.input), composer, anchor)
