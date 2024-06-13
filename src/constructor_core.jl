# Constructors for the Core schema.

construct_undefined_core_schema(constructor::Constructor, node::Node) =
    throw(ConstructorError("could not determine a constructor for the tag '$(node.tag)' in the Core schema", node.start_mark))

const construct_core_schema_str = construct_failsafe_schema_str

const construct_core_schema_seq = construct_failsafe_schema_seq

const construct_core_schema_map = construct_failsafe_schema_map

function construct_core_schema_null(constructor::Constructor, node::Node)
    value = construct_scalar(constructor, node)
    value == "null" || value == "Null" || value == "NULL" || value == "~" ? nothing :
    throw(ConstructorError("could not construct a null '$value' in the Core schema", node.start_mark))
end

function construct_core_schema_bool(constructor::Constructor, node::Node)
    value = construct_scalar(constructor, node)
    value == "true"  || value == "True"  || value == "TRUE"  ? true  :
    value == "false" || value == "False" || value == "FALSE" ? false :
    throw(ConstructorError("could not construct a bool '$value' in the Core schema", node.start_mark))
end

function construct_core_schema_int(constructor::Constructor, node::Node)
    value = construct_scalar(constructor, node)
    n =
        # hexadecimal
        length(value) > 2 && value[1] == '0' && value[2] == 'x' ? tryparse(Int, value[3:end], base=16) :
        # octal
        length(value) > 2 && value[1] == '0' && value[2] == 'o' ? tryparse(Int, value[3:end], base=8)  :
        # decimal
        tryparse(Int, value, base=10)
    n !== nothing ? n :
    throw(ConstructorError("could not construct a int '$value' in the Core schema", node.start_mark))
end

function construct_core_schema_float(construct::Constructor, node::Node)
    value = construct_scalar(constructor, node)
    # not a number
    (value == ".nan" || value == ".NaN" || value == ".NAN") && return NaN
    # infinity
    m = match(r"^([-+]?)(\.inf|\.Inf|\.INF)$", value)
    m !== nothing && return m.captures[1] == "-" ? -Inf : Inf
    # fixed or exponential
    x = tryparse(Float64, value)
    x !== nothing && isfinite(x) ? x :
    throw(ConstructorError("could not construct a float '$value' in the Core schema", node.start_mark))
end

const core_schema_constructors = Dict{Union{String, Nothing}, Function}(
    nothing                   => construct_undefined_core_schema,
    "tag:yaml.org,2002:str"   => construct_core_schema_str,
    "tag:yaml.org,2002:seq"   => construct_core_schema_seq,
    "tag:yaml.org,2002:map"   => construct_core_schema_map,
    "tag:yaml.org,2002:null"  => construct_core_schema_null,
    "tag:yaml.org,2002:bool"  => construct_core_schema_bool,
    "tag:yaml.org,2002:int"   => construct_core_schema_int,
    "tag:yaml.org,2002:float" => construct_core_schema_float,
)
