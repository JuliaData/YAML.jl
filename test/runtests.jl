#!/usr/bin/env julia

module YAMLTests

import YAML
import Base.Filesystem
using StringEncodings: encode, @enc_str
using Test

const tests = [
    "spec-02-01",
    "spec-02-02",
    "spec-02-03",
    "spec-02-04",
    "spec-02-05",
    "spec-02-06",
    "spec-02-07",
    "spec-02-08",
    "spec-02-09",
    "spec-02-10",
    "spec-02-11",
    "spec-02-12",
    "spec-02-13",
    "spec-02-14",
    "spec-02-15",
    "spec-02-16",
    "spec-02-17",
    "spec-02-18",
    "spec-02-19",
    "spec-02-20",
    "spec-02-21",
    "spec-02-22",
    "spec-02-23",
    "empty_scalar",
    "no_trailing_newline",
    "windows_newlines.crlf",
    "escape_sequences",
    "issue15",
    "issue30",
    "issue36",
    "issue39",
    "cartesian",
    "ar1",
    "ar1_cartesian",
    "merge-01",
    "version-colon",
    "multi-constructor",
    "utf-8-bom.crlf",
    "utf-32-be",
    "empty_tag",
    "empty_list_elem",
]

# ignore some test cases in write_and_load testing
const test_write_ignored = [
    "spec-02-17",
    "escape_sequences",
    "cartesian",
    "ar1",
    "ar1_cartesian",
    "multi-constructor"
]

# test custom tags
function construct_type_map(t::Symbol, constructor::YAML.Constructor,
                            node::YAML.Node)
    mapping = YAML.construct_mapping(constructor, node)
    mapping[:tag] = t
    mapping
end

function TestConstructor()
    pairs = [("!Cartesian", :Cartesian),
             ("!AR1", :AR1)]
    ret = YAML.SafeConstructor()
    for (t,s) in pairs
        YAML.add_constructor!(ret, t) do c, n
            construct_type_map(s, c, n)
        end
    end

    YAML.add_multi_constructor!(ret, "!addtag:") do constructor::YAML.Constructor, tag, node
        construct_type_map(Symbol(tag), constructor, node)
    end

    ret
end

const more_constructors = let
    pairs = [("!Cartesian", :Cartesian),
             ("!AR1", :AR1)]
    Dict{String,Function}([(t, (c, n) -> construct_type_map(s, c, n))
                           for (t, s) in pairs])
end

const multi_constructors = Dict{String, Function}(
    "!addtag:" => (c, t, n) -> construct_type_map(Symbol(t), c, n)
)

# write a file, then load its contents to be tested again
function write_and_load(data::Any)
    path = Filesystem.tempname() * ".yml" # path to a temporary file
    try
        YAML.write_file(path, data)
        return YAML.load_file(path, more_constructors)
    finally
        Filesystem.rm(path, force=true)
    end
end

const testdir = dirname(@__FILE__)
@testset for test in tests
    yaml_file_name = joinpath(testdir, "yaml/$test.yaml")
    julia_file_name = joinpath(testdir, "julia/$test.jl")

    yaml_string = read(yaml_file_name, String)
    expected = evalfile(julia_file_name)

    @testset "Load from File" begin
        @test begin
            data = YAML.load_file(
                yaml_file_name,
                TestConstructor()
            )
            isequal(data, expected)
        end
        @test begin
            dictData = YAML.load_file(
                yaml_file_name,
                more_constructors, multi_constructors
            )
            isequal(dictData, expected)
        end
    end

    @testset "Load from String" begin
        @test begin
            data = YAML.load(
                yaml_string,
                TestConstructor()
            )
            isequal(data, expected)
        end

        @test begin
            dictData = YAML.load(
                yaml_string,
                more_constructors, multi_constructors
            )
            isequal(dictData, expected)
        end
    end

    @testset "Load All from File" begin
        @test begin
            data = YAML.load_all_file(
                yaml_file_name,
                TestConstructor()
            )
            isequal(first(data), expected)
        end

        @test begin
            dictData = YAML.load_all_file(
                yaml_file_name,
                more_constructors, multi_constructors
            )
            isequal(first(dictData), expected)
        end
    end

    @testset "Load All from String" begin
        @test begin
            data = YAML.load_all(
                yaml_string,
                TestConstructor()
            )
            isequal(first(data), expected)
        end

        @test begin
            dictData = YAML.load_all(
                yaml_string,
                more_constructors, multi_constructors
            )
            isequal(first(dictData), expected)
        end
    end


    if !in(test, test_write_ignored)
        @testset "Writing" begin
            @test begin
                data = YAML.load_file(
                    yaml_file_name,
                    more_constructors
                )
                isequal(write_and_load(data), expected)
            end
        end
    else
        println("WARNING: I do not test the writing of $test")
    end
end

const encodings = [
    enc"UTF-8", enc"UTF-16BE", enc"UTF-16LE", enc"UTF-32BE", enc"UTF-32LE"
]
@testset for encoding in encodings
    data = encode("test", encoding)
    @test YAML.detect_encoding(IOBuffer(data)) == encoding
    @test YAML.load(IOBuffer(data)) == "test"

    #with explicit BOM
    data = encode("\uFEFFtest", encoding)
    @test YAML.detect_encoding(IOBuffer(data)) == encoding
    @test YAML.load(IOBuffer(data)) == "test"
end

@testset "multi_doc_bom" begin
    iterable = YAML.load_all("""
\ufeff---\r
test: 1
\ufeff---
test: 2

\ufeff---
test: 3
""")
    (val, state) = iterate(iterable)
    @test isequal(val, Dict("test" => 1))
    (val, state) = iterate(iterable, state)
    @test isequal(val, Dict("test" => 2))
    (val, state) = iterate(iterable, state)
    @test isequal(val, Dict("test" => 3))
    @test iterate(iterable, state) === nothing
end

# test that an OrderedDict is written in the correct order
using OrderedCollections, DataStructures
@test strip(YAML.yaml(OrderedDict(:c => 3, :b => 2, :a => 1))) == join(["c: 3", "b: 2", "a: 1"], "\n")

# test that arbitrary dicttypes can be parsed
const dicttypes = [
    Dict{Any,Any},
    Dict{String,Any},
    Dict{Symbol,Any},
    OrderedDict{String,Any},
    () -> DefaultDict{String,Any}(Missing),
]
@testset for dicttype in dicttypes
    data = YAML.load_file(
        joinpath(testdir, "nested-dicts.data"),
        more_constructors;
        dicttype=dicttype
    )
    if typeof(dicttype) <: Function
        dicttype = typeof(dicttype())
    end # check the return type of function dicttypes
    _key(k::String) = keytype(dicttype) == Symbol ? Symbol(k) : k # String or Symbol key
    @test typeof(data) == dicttype
    @test typeof(data[_key("outer")]) == dicttype
    @test typeof(data[_key("outer")][_key("inner")]) == dicttype
    @test data[_key("outer")][_key("inner")][_key("something_unrelated")] == "1" # for completeness

    # type-specific tests
    if dicttype <: OrderedDict
        @test [k for (k,v) in data] == [_key("outer"), _key("anything_later")] # correct order
    elseif [k for (k,v) in data] == [_key("outer"), _key("anything_later")]
        @warn "Test of OrderedDict might not be discriminative: the order is also correct in $dicttype"
    end
    if dicttype <: DefaultDict
        @test data[""] === missing
    end
end

const test_errors = [
    "invalid-tag"
]

@testset "YAML Errors" "error test = $test" for test in test_errors
    @test_throws YAML.ConstructorError YAML.load_file(
        joinpath(testdir, string(test, ".data")),
        TestConstructor()
    )
end

@testset "Custom Constructor" begin

    function MySafeConstructor()
        yaml_constructors = copy(YAML.yaml_jl_0_4_10_schema_constructors)
        delete!(yaml_constructors, nothing)
        YAML.Constructor(yaml_constructors)
    end


    function MyReallySafeConstructor()
        yaml_constructors = copy(YAML.yaml_jl_0_4_10_schema_constructors)
        delete!(yaml_constructors, nothing)
        ret = YAML.Constructor(yaml_constructors)
        YAML.add_multi_constructor!(ret, nothing) do constructor::YAML.Constructor, tag, node
            throw(YAML.ConstructorError(
                "could not determine a constructor for the tag '$(tag)' in the YAML.jl v0.4.10 schema",
                node.start_mark,
            ))
        end
        ret
    end

    yamlString = """
    Test: !test
        test1: !test data
        test2: !test2
            - test1
            - test2
    """

    expected = Dict{Any,Any}("Test" => Dict{Any,Any}("test2"=>["test1", "test2"],"test1"=>"data"))

    @test isequal(YAML.load(yamlString, MySafeConstructor()), expected)
    @test_throws YAML.ConstructorError YAML.load(
        yamlString,
        MyReallySafeConstructor()
    )
end


# also check that things break correctly
@test_throws YAML.ConstructorError YAML.load_file(
    joinpath(testdir, "nested-dicts.data"),
    more_constructors;
    dicttype=Dict{Float64,Any}
)

@test_throws YAML.ConstructorError YAML.load_file(
    joinpath(testdir, "nested-dicts.data"),
    more_constructors;
    dicttype=Dict{Any,Float64}
)

@test_throws ArgumentError YAML.load_file(
    joinpath(testdir, "nested-dicts.data"),
    more_constructors;
    dicttype=(mistaken_argument) -> DefaultDict{String,Any}(mistaken_argument)
)

@test_throws ArgumentError YAML.load_file(
    joinpath(testdir, "nested-dicts.data"),
    more_constructors;
    dicttype=() -> 3.0 # wrong type
)

@test_throws YAML.ScannerError YAML.load("x: %")
if VERSION >= v"1.8"
    @test_throws "found character '%' that cannot start any token" YAML.load("x: %")
end

# issue 81
dict_content = ["key1" => [Dict("subkey1" => "subvalue1", "subkey2" => "subvalue2"), Dict()], "key2" => "value2"]
order_one = OrderedDict(dict_content...)
order_two = OrderedDict(dict_content[[2,1]]...) # reverse order
@test YAML.yaml(order_one) != YAML.yaml(order_two)
@test YAML.load(YAML.yaml(order_one)) == YAML.load(YAML.yaml(order_two))

# issue 89 - quotes in strings
@test YAML.load(YAML.yaml(Dict("a" => """a "quoted" string""")))["a"] == """a "quoted" string"""
@test YAML.load(YAML.yaml(Dict("a" => """a \\"quoted\\" string""")))["a"] == """a \\"quoted\\" string"""

# issue 108 - dollar signs in single-line strings
@test YAML.yaml("foo \$ bar") == "\"foo \$ bar\"\n"

@test YAML.load(YAML.yaml(Dict("a" => "")))["a"] == ""
@test YAML.load(YAML.yaml(Dict("a" => "nl at end\n")))["a"] == "nl at end\n"
@test YAML.load(YAML.yaml(Dict("a" => "one\nnl\n")))["a"] == "one\nnl\n"
@test YAML.load(YAML.yaml(Dict("a" => "many\nnls\n\n\n")))["a"] == "many\nnls\n\n\n"
@test YAML.load(YAML.yaml(Dict("a" => "no\ntrailing\nnls")))["a"] == "no\ntrailing\nnls"
@test YAML.load(YAML.yaml(Dict("a" => "foo\n\"bar\\'")))["a"] == "foo\n\"bar\\'"

@test YAML.load(YAML.yaml(Dict("a" => Dict()))) == Dict("a" => Dict())
@test YAML.load(YAML.yaml(Dict("a" => []))) == Dict("a" => [])

# issue 114 - gracefully handle extra commas in flow collections
@testset "issue114" begin
    @test YAML.load("[3,4,]") == [3,4]
    @test YAML.load("{a:4,b:5,}") == Dict("a" => 4, "b" => 5)
    @test YAML.load("[?a:4, ?b:5]") == [Dict("a" => 4), Dict("b" => 5)]
    @test_throws YAML.ParserError YAML.load("[3,,4]")
    @test_throws YAML.ParserError YAML.load("{a: 3,,b:3}")
end

@testset "issue 125 (test_throw)" begin
    @test_throws YAML.ScannerError YAML.load(""" ''' """)
    @test_throws YAML.ScannerError YAML.load(""" ''''' """)
    @test_throws YAML.ParserError YAML.load(""" ''a'' """)
    @test_throws YAML.ScannerError YAML.load(""" '''a'' """)
end

# issue 129 - Comment only content
@testset "issue129" begin
    @test YAML.load("#") === nothing
    @test isempty(YAML.load_all("#"))
end

# issue 132 - load_all fails on windows
@testset "issue132" begin
    input = """
            ---
            creator: LAMMPS
            timestep: 0
            ...
            ---
            creator: LAMMPS
            timestep: 1
            ...
            """
    expected = [Dict("creator" => "LAMMPS", "timestep" => 0),
                Dict("creator" => "LAMMPS", "timestep" => 1)]
    @test collect(YAML.load_all(input)) == expected
end

# issue #148 - warn unknown directives
@testset "issue #148" begin
    @test (@test_logs (:warn, """unknown directive name: "FOO" at line 1, column 4. We ignore this.""") YAML.load("""%FOO  bar baz\n\n--- "foo\"""")) == "foo"
    @test (@test_logs (:warn, """unknown directive name: "FOO" at line 1, column 4. We ignore this.""") (:warn, """unknown directive name: "BAR" at line 2, column 4. We ignore this.""") YAML.load("""%FOO\n%BAR\n--- foo""")) == "foo"
end

# issue #143 - load empty file
@testset "issue #143" begin
    @test YAML.load("") === nothing
    @test isempty(YAML.load_all(""))
end

# issue #144
@testset "issue #144" begin
    @test YAML.load("---") === nothing
end

# issue #132
@testset "issue #132" begin
    docs_expected = evalfile(joinpath(testdir, "julia/issue132.jl"))
    open(joinpath(testdir, "yaml/issue132.lf.yaml"), "r") do io
        docs = YAML.load_all(io)
        doc, i = iterate(docs)
        @test isequal(doc, docs_expected[1])
        doc, i = iterate(docs, i)
        @test isequal(doc, docs_expected[2])
        @test iterate(docs, i) === nothing
    end
    # open(joinpath(testdir, "yaml/issue132.crlf.yaml"), "r") do io
    #     docs = YAML.load_all(io)
    #     doc, i = iterate(docs)
    #     @test isequal(doc, docs_expected[1])
    #     doc, i = iterate(docs, i)
    #     @test isequal(doc, docs_expected[2])
    #     @test iterate(docs, i) === nothing
    # end
end

# issue #226 - loadall stops on a null document
@testset "issue #226" begin
    @test collect(YAML.load_all("null")) == [nothing]
    input = """
            ---
            1
            ---
            null
            ---
            2
            """
    expected = [1, nothing, 2]
    @test collect(YAML.load_all(input)) == expected
end

@testset "failsafe schema" begin
end

@testset "JSON schema" begin
    @test YAML.tryparse_json_schema_null("A null") isa YAML.JSONSchemaParseError
    @test YAML.tryparse_json_schema_null("null") === nothing
    @test YAML.tryparse_json_schema_null("Null") isa YAML.JSONSchemaParseError
    @test YAML.tryparse_json_schema_bool("true") == true
    @test YAML.tryparse_json_schema_bool("True") isa YAML.JSONSchemaParseError
    @test YAML.tryparse_json_schema_bool("false") == false
    @test YAML.tryparse_json_schema_bool("FALSE") isa YAML.JSONSchemaParseError
    @test YAML.tryparse_json_schema_int("0") == 0
    @test YAML.tryparse_json_schema_int("7") == 7
    @test YAML.tryparse_json_schema_int("58") == 58
    @test YAML.tryparse_json_schema_int("-19") == -19
    @test YAML.tryparse_json_schema_int("0o7") isa YAML.JSONSchemaParseError
    @test YAML.tryparse_json_schema_int("0x3A") isa YAML.JSONSchemaParseError
    @test YAML.tryparse_json_schema_float("0.") == 0.0
    @test YAML.tryparse_json_schema_float("-0.0") == -0.0
    @test YAML.tryparse_json_schema_float(".5") isa YAML.JSONSchemaParseError
    @test YAML.tryparse_json_schema_float("12e03") == 12000
    @test YAML.tryparse_json_schema_float("+12e03") isa YAML.JSONSchemaParseError
    @test YAML.tryparse_json_schema_float("-2E+05") == -200000
    @test YAML.tryparse_json_schema_float(".inf") isa YAML.JSONSchemaParseError
    @test YAML.tryparse_json_schema_float("-.Inf") isa YAML.JSONSchemaParseError
    @test YAML.tryparse_json_schema_float("+.INF") isa YAML.JSONSchemaParseError
    @test YAML.tryparse_json_schema_float(".NAN") isa YAML.JSONSchemaParseError
    @test YAML.tryparse_json_schema_float("+12.3") isa YAML.JSONSchemaParseError

end

@testset "Core schema" begin
    @test YAML.tryparse_core_schema_null("A null") isa YAML.CoreSchemaParseError
    @test YAML.tryparse_core_schema_null("null") === nothing
    @test YAML.tryparse_core_schema_bool("true") == true
    @test YAML.tryparse_core_schema_bool("True") == true
    @test YAML.tryparse_core_schema_bool("false") == false
    @test YAML.tryparse_core_schema_bool("FALSE") == false
    @test YAML.tryparse_core_schema_int("0") == 0
    @test YAML.tryparse_core_schema_int("7") == 7
    @test YAML.tryparse_core_schema_int("58") == 58
    @test YAML.tryparse_core_schema_int("-19") == -19
    @test YAML.tryparse_core_schema_float("0.") == 0.0
    @test YAML.tryparse_core_schema_float("-0.0") == -0.0
    @test YAML.tryparse_core_schema_float(".5") == 0.5
    @test YAML.tryparse_core_schema_float("+12e03") == 12000
    @test YAML.tryparse_core_schema_float("-2E+05") == -200000
    @test YAML.tryparse_core_schema_float(".inf") == Inf
    @test YAML.tryparse_core_schema_float("-.Inf") == -Inf
    @test YAML.tryparse_core_schema_float("+.INF") == Inf
    @test YAML.tryparse_core_schema_float(".NAN") |> isnan
end

@testset "YAML.jl v0.4.10 schema" begin
end

end  # module
