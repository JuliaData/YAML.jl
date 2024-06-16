# Error for constructors

<<<<<<< HEAD
struct ConstructorError
    context      :: Union{String, Nothing}
    context_mark :: Union{Mark,   Nothing}
    problem      :: Union{String, Nothing}
    problem_mark :: Union{Mark,   Nothing}
    note         :: Union{String, Nothing}
=======
struct ConstructorError <: Exception
    context::Union{String, Nothing}
    context_mark::Union{Mark, Nothing}
    problem::Union{String, Nothing}
    problem_mark::Union{Mark, Nothing}
    note::Union{String, Nothing}

    function ConstructorError(context=nothing, context_mark=nothing,
                              problem=nothing, problem_mark=nothing,
                              note=nothing)
        new(context, context_mark, problem, problem_mark, note)
    end

>>>>>>> master
end

# `context` at `context_mark`: `problem` at `problem_mark`
ConstructorError(context, context_mark, problem, problem_mark) =
    ConstructorError(context, context_mark, problem, problem_mark, nothing)

# `problem` at `problem_mark`
ConstructorError(problem, problem_mark) =
    ConstructorError(nothing, nothing, problem, problem_mark)

function show(io::IO, error::ConstructorError)
    if error.context !== nothing
        print(io, error.context, " at ", error.context_mark, ": ")
    end
    print(io, error.problem, " at ", error.problem_mark)
end

# Constructor

mutable struct Constructor
    constructed_objects     :: Dict{Node, Any}
    recursive_objects       :: Set{Node}
    yaml_constructors       :: Dict{Union{String, Nothing}, Function}
    yaml_multi_constructors :: Dict{Union{String, Nothing}, Function}

    Constructor(
        # Can we add type annotations?
        single_constructors = Dict{String, Function}(),
        multi_constructors  = Dict{String, Function}(),
    ) = new(
        Dict{Node, Any}(),
        Set{Node}(),
        convert(Dict{Union{String, Nothing}, Function}, single_constructors),
        convert(Dict{Union{String, Nothing}, Function}, multi_constructors),
    )
end

Constructor(::Nothing) = Constructor(Dict{String, Function}())

# add a constructor function of the specific tag
function add_constructor!(func::Function, constructor::Constructor, tag::Union{String, Nothing})
    constructor.yaml_constructors[tag] = func
    constructor
end

# add a multi constructor function of the specific tag
function add_multi_constructor!(func::Function, constructor::Constructor, tag::Union{String, Nothing})
    constructor.yaml_multi_constructors[tag] = func
    constructor
end

# Paalon: I don't know what is safe.
SafeConstructor(
    # Can we add more specific type annotations?
    constructors       :: Dict = Dict(),
    multi_constructors :: Dict = Dict(),
) = Constructor(
    merge(copy(yaml_jl_0_4_10_schema_constructors), constructors),
    multi_constructors,
)

# construct_document

function construct_document(constructor::Constructor, node::Node)
    data = construct_object(constructor, node)
    empty!(constructor.constructed_objects)
    empty!(constructor.recursive_objects)
    data
end

# construct_object

function construct_object(constructor::Constructor, node::Node)
    haskey(constructor.constructed_objects, node) && return constructor.constructed_objects[node]

    node in constructor.recursive_objects && throw(ConstructorError("found unconstructable recursive node", node.start_mark))

    push!(constructor.recursive_objects, node)
    node_constructor = nothing
    tag_suffix = nothing
    if haskey(constructor.yaml_constructors, node.tag)
        node_constructor = constructor.yaml_constructors[node.tag]
    else
        for (tag_prefix, node_const) in constructor.yaml_multi_constructors
            if tag_prefix !== nothing && startswith(node.tag, tag_prefix)
                tag_suffix = node.tag[length(tag_prefix) + 1:end]
                node_constructor = node_const
                break
            end
        end

        if node_constructor === nothing
            if haskey(constructor.yaml_multi_constructors, nothing)
                tag_suffix = node.tag
                node_constructor = constructor.yaml_multi_constructors[nothing]
            elseif haskey(constructor.yaml_constructors, nothing)
                node_constructor = constructor.yaml_constructors[nothing]
            elseif node isa ScalarNode
                node_constructor = construct_scalar
            elseif node isa SequenceNode
                node_constructor = construct_sequence
            elseif node isa MappingNode
                node_constructor = construct_mapping
            end
        end
    end

    if tag_suffix === nothing
        data = node_constructor(constructor, node)
    else
        data = node_constructor(constructor, tag_suffix, node)
    end

    # TODO: Handle generators/iterators

    constructor.constructed_objects[node] = data
    delete!(constructor.recursive_objects, node)

    data
end

# construct_scalar

function construct_scalar(constructor::Constructor, node::Node)
    node isa ScalarNode || throw(ConstructorError("expected a scalar node, but found $(typeof(node))", node.start_mark))
    node.value
end

# construct_sequence

function construct_sequence(constructor::Constructor, node::Node)
    node isa SequenceNode || throw(ConstructorError("expected a sequence node, but found $(typeof(node))", node.start_mark))
    [construct_object(constructor, child) for child in node.value]
end

# flatten_mapping

# TODO:
# This function processes the following 2 tags:
# - "tag:yaml.org,2002:merge"
# - "tag:yaml.org,2002:value"
# So, we need to investigate.

function flatten_mapping(node::MappingNode)
    # TODO:
    # The variable name `merge` is exported from Julia `Base`
    # thus it should be renamed for disambiguation.
    merge = []
    index = 1
    while index ≤ length(node.value)
        key_node, value_node = node.value[index]
        if key_node.tag == "tag:yaml.org,2002:merge"
            node.value = node.value[setdiff(axes(node.value, 1), index)]
            if value_node isa MappingNode
                flatten_mapping(value_node)
                append!(merge, value_node.value)
            elseif value_node isa SequenceNode
                submerge = []
                for subnode in value_node.value
                    subnode isa MappingNode || throw(ConstructorError(
                        "while constructing a mapping", node.start_mark,
                        "expected a mapping node, but found $(typeof(subnode))", subnode.start_mark,
                    ))
                    flatten_mapping(subnode)
                    push!(submerge, subnode.value)
                    for value in reverse(submerge)
                        append!(merge, value)
                    end
                end
            end
        elseif key_node.tag == "tag:yaml.org,2002:value"
            key_node.tag = "tag:yaml.org,2002:str"
            index += 1
        else
            index += 1
        end
    end

    if !isempty(merge)
        node.value = vcat(merge, node.value)
    end
    nothing
end

# construct_mapping

function construct_mapping(dicttype::Union{Type, Function}, constructor::Constructor, node::MappingNode)
    flatten_mapping(node)
    mapping = dicttype()
    for (key_node, value_node) in node.value
        key = construct_object(constructor, key_node)
        value = construct_object(constructor, value_node)
        if !(value isa keytype(mapping))
            try
                key = keytype(mapping)(key) # try to cast
            catch
                throw(ConstructorError("Cannot cast $key to the key type of $dicttype", node.start_mark))
            end
        end
        try
            mapping[key] = value
        catch
            throw(ConstructorError("Cannot store $key=>$value in $dicttype", node.start_mark))
        end
    end
    mapping
end

construct_mapping(constructor::Constructor, node::Node) = construct_mapping(Dict{Any,Any}, constructor, node)

# custom_mapping
# create a construct_mapping instance for a specific dicttype

custom_mapping(dicttype::Type{D}) where D <: AbstractDict =
    (constructor::Constructor, node::Node) -> construct_mapping(dicttype, constructor, node)

function custom_mapping(dicttype::Function)
    dicttype_test = try
        dicttype()
    catch
        throw(ArgumentError("The dicttype Function cannot be called without arguments"))
    end
    dicttype_test isa AbstractDict || throw(ArgumentError("The dicttype Function does not return an AbstractDict"))
    (constructor::Constructor, node::Node) -> construct_mapping(dicttype, constructor, node)
end

# Definition of constructors for each schema.
include("constructor_failsafe.jl")
include("constructor_json.jl")
include("constructor_core.jl")
include("constructor_yaml_jl_0_4_10.jl")
