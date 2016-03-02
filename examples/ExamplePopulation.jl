type ExampleIndividual <: Individual
  genome::Array{Int64, 1}
  fitness::Float64
  code


  function ExampleIndividual(size::Int64, max_value::Int64)
    genome = rand(1:max_value, size)
    return new(genome, realmax(Float64), nothing)
  end

  ExampleIndividual(genome::Array{Int64, 1}) = new(genome, realmax(Float64), nothing)
end

type ExamplePopulation <: Population
  individuals::Array{ExampleIndividual, 1}
  best_fitness::Float64
  best_ind::ExampleIndividual
  best_at_eval::Int64
  totalevals::Int64

  function ExamplePopulation(population_size::Int64, genome_size::Int64,
                             best_fitness::Float64=realmax(Float64),
                             best_individual::Union{ExampleIndividual,Void}=nothing,
                             best_at_eval::Int64=0, totalevals::Int64=0)
    individuals = Array(ExampleIndividual, 0)
    for i=1:population_size
      push!(individuals, ExampleIndividual(genome_size, 1000))
    end

    if best_individual == nothing
      best_individual = ExampleIndividual(genome_size, 1000)
    end
    return new(individuals, best_fitness, best_individual, best_at_eval, totalevals)
  end
end
