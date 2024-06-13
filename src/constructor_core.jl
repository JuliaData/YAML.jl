# Constructors for the Core schema.

# Parsing utils

struct CoreSchemaParseError <: Exception end

function tryparse_core_schema_null(str::String)::Union{Nothing, CoreSchemaParseError}
    # nothing
    str == "null" || str == "Null" || str == "NULL" || str == "~" ? nothing :
    # error
    CoreSchemaParseError()
end

function tryparse_core_schema_bool(str::String)::Union{Bool, CoreSchemaParseError}
    # true
    str == "true"  || str == "True"  || str == "TRUE"  ? true  :
    # false
    str == "false" || str == "False" || str == "FALSE" ? false :
    # error
    CoreSchemaParseError()
end

function tryparse_core_schema_int(str::String)::Union{Int, CoreSchemaParseError}
    n =
    # hexadecimal
    length(str) > 2 && str[1] == '0' && str[2] == 'x' ? tryparse(Int, str[3:end], base=16) :
    # octal
    length(str) > 2 && str[1] == '0' && str[2] == 'o' ? tryparse(Int, str[3:end], base=8)  :
    # decimal
    tryparse(Int, str, base=10)
    # int
    n !== nothing ? n :
    # error
    CoreSchemaParseError()
end

function tryparse_core_schema_float(str::String)::Union{Float64, CoreSchemaParseError}
    # not a number
    (str == ".nan" || str == ".NaN" || str == ".NAN") && return NaN
    # infinity
    m = match(r"^([-+]?)(\.inf|\.Inf|\.INF)$", str)
    m !== nothing && return m.captures[1] == "-" ? -Inf : Inf
    # fixed or exponential
    x = tryparse(Float64, str)
    # float
    x !== nothing && isfinite(x) ? x :
    # error
    CoreSchemaParseError()
end

# Construct functions

construct_undefined_core_schema(constructor::Constructor, node::Node) =
    throw(ConstructorError("could not determine a constructor for the tag '$(node.tag)' in the Core schema", node.start_mark))

const construct_core_schema_str = construct_failsafe_schema_str

const construct_core_schema_seq = construct_failsafe_schema_seq

const construct_core_schema_map = construct_failsafe_schema_map

function construct_core_schema_null(constructor::Constructor, node::Node)::Nothing
    str = construct_scalar(constructor, node)
    n = tryparse_core_schema_null(str)
    n isa CoreSchemaParseError &&
    throw(ConstructorError("could not construct a null '$str' in the Core schema", node.start_mark))
    n
end

function construct_core_schema_bool(constructor::Constructor, node::Node)::Bool
    str = construct_scalar(constructor, node)
    b = tryparse_core_schema_bool(str)
    b isa CoreSchemaParseError &&
    throw(ConstructorError("could not construct a bool '$str' in the Core schema", node.start_mark))
    b
end

function construct_core_schema_int(constructor::Constructor, node::Node)::Int
    str = construct_scalar(constructor, node)
    n = tryparse_core_schema_int(str)
    n isa CoreSchemaParseError &&
    throw(ConstructorError("could not construct an int '$str' in the Core schema", node.start_mark))
    n
end

function construct_core_schema_float(construct::Constructor, node::Node)::Float64
    str = construct_scalar(constructor, node)
    x = tryparse_core_schema_float(str)
    x isa CoreSchemaParseError &&
    throw(ConstructorError("could not construct a float '$str' in the Core schema", node.start_mark))
    x
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
