using Base.Test

import Base.==

#
# Test deseerialization into primitive fields, and test optional fields
#

immutable NameHrAvg
    name::AbstractString
    hr::Nullable{Int}
    avg::Float64
end

==(a::NameHrAvg, b::NameHrAvg) = a.name == b.name && a.avg == b.avg &&
    (isnull(a.hr) && isnull(b.hr) || !isnull(a.hr) && !isnull(b.hr) && get(a.hr) == get(b.hr))

#
# Test deserialization of array fields
#
immutable Teams
    american::Vector{AbstractString}
    national::Vector{AbstractString}
end
global Teams

==(a::Teams, b::Teams) = a.american == b.american && a.national == b.national

#
# Test deserialization of composite fields
#

immutable CompositeTeams
    teams::Teams
end

==(a::CompositeTeams, b::CompositeTeams) = a.teams == b.teams

#
# Test all listed files
#

deserialization_tests = [
    ("deserialize-01", NameHrAvg("Mark McGwire", Nullable{Int}(65), 0.278)),

    ("deserialize-02",
        Teams(ASCIIString["Boston Red Sox", "Detroit Tigers", "New York Yankees"],
              ASCIIString["New York Mets", "Chicago Cubs", "Atlanta Braves"])),

    ("deserialize-03", NameHrAvg("Mark McGwire", Nullable{Int}(), 0.278)),

    ("deserialize-04",
        CompositeTeams(Teams(ASCIIString["Boston Red Sox", "Detroit Tigers", "New York Yankees"],
                             ASCIIString["New York Mets", "Chicago Cubs", "Atlanta Braves"])))
]

for test in deserialization_tests
    filename = test[1]
    expected = test[2]

    @printf("%s: ", filename)

    datatype = typeof(expected)
    data = YAML.load_file(joinpath(testdir, string(filename, ".data")))
    actual = YAML.deserialize(datatype, data)

    if actual == expected
        @printf("PASSED\n")
    else
        @printf("FAILED\n")
        @printf("Expected:\n%s\nParsed:\n%s\n",
                expected, actual)
    end
end

