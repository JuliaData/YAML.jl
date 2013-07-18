#!/usr/bin/env julia

push!(LOAD_PATH, joinpath(pwd(), "..", "src"))

import YAML

tests = [
    "spec-02-01",
    "spec-02-02",
    "spec-02-03",
    "spec-02-04",
    "spec-02-05",
    "spec-02-06",
    "spec-02-07",
    "spec-02-08",
    "spec-02-09",
    "spec-02-10"
]



for test in tests
    data = YAML.load(open(string(test, ".data")))
    expected = evalfile(string(test, ".expected"))
    if data != expected
        @printf("%s: FAILED\n", test)
        @printf("Expected:\n%s\nParsed:\n%s\n",
                expected, data)
    else
        @printf("%s: PASSED\n", test)
    end
end


