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
    "windows_newlines",
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
    "utf-8-bom",
    "utf-32-be",
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


function equivalent(xs::AbstractDict, ys::AbstractDict)
    if Set(collect(keys(xs))) != Set(collect(keys(ys)))
        @info "Not equivalent" Set(collect(keys(xs))) Set(collect(keys(ys)))
        return false
    end

    for k in keys(xs)
        if !equivalent(xs[k], ys[k])
            @info "Not equivalent" xs[k] ys[k]
            return false
        end
    end

    true
end


function equivalent(xs::AbstractArray, ys::AbstractArray)
    if length(xs) != length(ys)
        @info "Not equivalent" length(xs) length(ys)
        return false
    end

    for (x, y) in zip(xs, ys)
        if !equivalent(x, y)
            @info "Not equivalent" x y
            return false
        end
    end

    true
end


function equivalent(x::Float64, y::Float64)
    isnan(x) && isnan(y) ? true : x == y
end


function equivalent(x::AbstractString, y::AbstractString)
    while endswith(x, "\n")
        x = x[1:end-1] # trailing newline characters are ambiguous
    end
    while endswith(y, "\n")
        y = y[1:end-1]
    end
    x == y
end

function equivalent(x, y)
    x == y
end


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
    yamlString = open(joinpath(testdir, string(test, ".data"))) do f
        chomp(read(f, String))
    end
    expected = evalfile(joinpath(testdir, string(test, ".expected")))

    @testset "Load from File" begin
        @test begin
            data = YAML.load_file(
                joinpath(testdir, string(test, ".data")),
                TestConstructor()
            )
            equivalent(data, expected)
        end
        @test begin
            dictData = YAML.load_file(
                joinpath(testdir, string(test, ".data")),
                more_constructors, multi_constructors
            )
            equivalent(dictData, expected)
        end
    end

    @testset "Load from String" begin
        @test begin
            data = YAML.load(
                yamlString,
                TestConstructor()
            )
            equivalent(data, expected)
        end

        @test begin
            dictData = YAML.load(
                yamlString,
                more_constructors, multi_constructors
            )
            equivalent(dictData, expected)
        end
    end

    @testset "Load All from File" begin
        @test begin
            data = YAML.load_all_file(
                joinpath(testdir, string(test, ".data")),
                TestConstructor()
            )
            equivalent(first(data), expected)
        end

        @test begin
            dictData = YAML.load_all_file(
                joinpath(testdir, string(test, ".data")),
                more_constructors, multi_constructors
            )
            equivalent(first(dictData), expected)
        end
    end

    @testset "Load All from String" begin
        @test begin
            data = YAML.load_all(
                yamlString,
                TestConstructor()
            )
            equivalent(first(data), expected)
        end

        @test begin
            dictData = YAML.load_all(
                yamlString,
                more_constructors, multi_constructors
            )
            equivalent(first(dictData), expected)
        end
    end


    if !in(test, test_write_ignored)
        @testset "Writing" begin
            @test begin
                data = YAML.load_file(
                    joinpath(testdir, string(test, ".data")),
                    more_constructors
                )
                equivalent(write_and_load(data), expected)
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
    @test equivalent(val, Dict("test" => 1))
    (val, state) = iterate(iterable, state)
    @test equivalent(val, Dict("test" => 2))
    (val, state) = iterate(iterable, state)
    @test equivalent(val, Dict("test" => 3))
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
        yaml_constructors = copy(YAML.default_yaml_constructors)
        delete!(yaml_constructors, nothing)
        YAML.Constructor(yaml_constructors)
    end


    function MyReallySafeConstructor()
        yaml_constructors = copy(YAML.default_yaml_constructors)
        delete!(yaml_constructors, nothing)
        ret = YAML.Constructor(yaml_constructors)
        YAML.add_multi_constructor!(ret, nothing) do constructor::YAML.Constructor, tag, node
            throw(YAML.ConstructorError(nothing, nothing,
                "could not determine a constructor for the tag '$(tag)'",
                node.start_mark))
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

    @test equivalent(YAML.load(yamlString, MySafeConstructor()), expected)
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

end  # module
