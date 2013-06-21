

# TODO:
# This is a punt for now. It does not handle any sort of custom resolving tags,
# only matching default implicits.


const DEFAULT_SCALAR_TAG = "tag:yaml.org,2002:str"
const DEFAULT_SEQUENCE_TAG = "tag:yaml.org,2002:seq"
const DEFAULT_MAPPING_TAG = "tag:yaml.org,2002:map"
 

const default_implicit_resolvers =
    [
         ("tag:yaml.org,2002:bool",
          r"^(?:yes|Yes|YES|no|No|NO
            |true|True|TRUE|false|False|FALSE
            |on|On|ON|off|Off|OFF)$"x),

         ("tag:yaml.org,2002:float",
          r"^(?:[-+]?(?:[0-9][0-9_]*)\.[0-9_]*(?:[eE][-+][0-9]+)?
            |\.[0-9_]+(?:[eE][-+][0-9]+)?
            |[-+]?[0-9][0-9_]*(?::[0-5]?[0-9])+\.[0-9_]*
            |[-+]?\.(?:inf|Inf|INF)
            |\.(?:nan|NaN|NAN))$"x),

         ("tag:yaml.org,2002:int",
          r"^(?:[-+]?0b[0-1_]+
            |[-+]?0[0-7_]+
            |[-+]?(?:0|[1-9][0-9_]*)
            |[-+]?0x[0-9a-fA-F_]+
            |[-+]?[1-9][0-9_]*(?::[0-5]?[0-9])+)$"x),

         ("tag:yaml.org,2002:merge",
          r"^(?:<<)$"),

         ("tag:yaml.org,2002:null",
          r"^(?: ~
            |null|Null|NULL
            | )$"x),

         ("tag:yaml.org,2002:timestamp",
          r"^(?:[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]
            |[0-9][0-9][0-9][0-9] -[0-9][0-9]? -[0-9][0-9]?
            (?:[Tt]|[ \t]+)[0-9][0-9]?
            :[0-9][0-9] :[0-9][0-9] (?:\.[0-9]*)?
            (?:[ \t]*(?:Z|[-+][0-9][0-9]?(?::[0-9][0-9])?))?)$"x),

         ("tag:yaml.org,2002:value",
          r"^(?:=)$"),

         ("tag:yaml.org,2002:yaml",
          r"^(?:!|&|\*)$")
    ]


type Resolver
    implicit_resolvers::Vector

    function Resolver()
        new(copy(default_implicit_resolvers))
    end
end


function resolve(resolver::Resolver, ::Type{ScalarNode}, value, implicit)
    if implicit[0]
        for (tag, pat) in resolver.implicit_resolvers
            if ismatch(pat, value)
                return tag
            end
        end
    end

    DEFAULT_SCALAR_TAG
end


function resolve(resolver::Resolver, ::Type{SequenceNode}, value, implicit)
    DEFAULT_SEQUENCE_TAG
end

function resolve(resolver::Resolver, ::Type{MappingNode}, value, implicit)
    DEFAULT_MAPPING_TAG
end

