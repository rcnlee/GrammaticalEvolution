module GrammaticalEvolution

import Base.*
import Base.sort!
import Base.getindex
import Base.setindex!
import Base.length
import Base.endof
import Base.isless
import Base.push!
import Base.pop!

export Individual, Population
export select_two_individuals, one_point_crossover, mutate!, evaluate!, generate, transform
export length, getindex, endof, setindex!, isless, genome_iterator
export MaxWrapException

include("EBNF.jl")

export Grammar, @grammar, Rule, AndRule, OrRule, parseGrammar
export RangeRule, ReferencedRule, ExprRule, RepeatedRule, Terminal #rcnlee added

type MaxWrapException <: Exception end

abstract Individual
abstract Population

#rcnlee
include("../examples/ExamplePopulation.jl")
export ExampleIndividual, ExamplePopulation
#/rcnlee

# methods that have to be supported by subclasses of population
length{T <: Population}(pop::T) = length(pop.individuals)
getindex{T <: Population}(pop::T, indices...) = pop.individuals[indices...]
push!{T <: Population, S <: Individual}(pop::T, ind::S) = push!(pop.individuals, ind)
pop!{T <: Population}(pop::T) = pop!(pop.individuals)

# methods that have to be supported by subclasses of individuals
length{T <: Individual}(ind::T) = length(ind.genome)
endof{T <: Individual}(ind::T) = endof(ind.genome)
getindex{T <: Individual}(ind::T, indices...) = ind.genome[indices...]
setindex!{T <: Individual}(ind::T, value::Int64, indices) = ind.genome[indices] = value
isless{T <: Individual}(ind1::T, ind2::T) = ind1.fitness < ind2.fitness
getFitness{T <: Individual}(ind::T) = ind.fitness
getCode{T <: Individual}(ind::T) = ind.code
# evaluate(ind::Individual) = nothing
evaluate!{T <: Individual}(grammar::Grammar, ind::T, args...) = error("evaluate! not defined!")

# TODO: this should be distributed
function evaluate!{PopulationType <: Population}(grammar::Grammar, pop::PopulationType, args...)
  for i=1:length(pop)
    if getCode(pop[i]) == nothing #uninitialized
      evaluate!(grammar, pop[i], pop, args...)
    end
  end
end

function sort!{PopulationType <: Population}(pop::PopulationType)
  sort!(pop.individuals)
end

function select_two_individuals{T <: Individual}(individuals::Array{T,1})
  # randomly select two individuals from a population
  while true
    i1 = rand(1:length(individuals))
    i2 = rand(1:length(individuals))

    # make sure the two individuals are not the same
    if i1 != i2
      return (i1, i2)
    end
  end
end

function one_point_crossover{IndividualType <: Individual}(ind1::IndividualType, ind2::IndividualType)
  cross_point = rand(1:length(ind1))
  g1 = vcat(ind1[1:cross_point-1], ind2[cross_point:end])
  g2 = vcat(ind2[1:cross_point-1], ind1[cross_point:end])

  return (IndividualType(g1), IndividualType(g2), cross_point)
end

function mutate!(ind::Individual, mutation_rate::Float64; max_value=1000)
  for i=1:length(ind)
    if rand() < mutation_rate
      ind[i] = rand(1:max_value)
    end
  end
end

"""
top_keep is fraction of population (sorted by fitness) that is directly kept
rand_frac is fraction of new population that is randomly generated
top_seed is fraction of population (sorted by fitness) that is used to seed the remaining part of population
prob_mutation is the probability of mutating an individual
mutation_rate is the mutation rate on a mutating individual
"""
function generate{PopulationType <: Population}(grammar::Grammar, population::PopulationType,   
    top_keep::Float64, top_seed::Float64, rand_frac::Float64, prob_mutation::Float64, 
    mutation_rate::Float64, args...)
  # sort population
  sort!(population)

  #rcnlee: changed#####
  # take top performers for cross-over
  n_keep = floor(Int64, length(population)*top_keep) #top n_keep is copied from top_performers
  n_seed = floor(Int64, length(population)*top_seed) #top n_seed is used to seed remaining generation
  n_rand = floor(Int64, length(population)*rand_frac) #rand_frac fraction of population is random
  top_performers = population[1:n_seed] #candidates for cross-over and mutation

  # create a new population
  genome_size = length(population[1])
  
  #randomly sample n_rand individuals
  new_population = PopulationType(n_rand, genome_size,
                                  population.best_fitness, #maintain info from previous generation
                                  population.best_ind,
                                  population.best_at_eval,
                                  population.totalevals) #random population of size n_rand

  for i = 1:n_keep #n_keep of old population is directly copied
    push!(new_population, population[i])
  end
  ##########

  # fill in the rest by mating top performers
  while length(new_population) < length(population)
    (i1, i2) = select_two_individuals(top_performers)
    (ind1, ind2) = one_point_crossover(top_performers[i1], top_performers[i2])
    push!(new_population, ind1)
    push!(new_population, ind2)
  end

  # mutate the crossed-over portion of population 
  for j=(n_rand+n_keep+1):length(population)
    if rand() < prob_mutation
      mutate!(new_population[j], mutation_rate)
    end
  end

  # evaluate new population and re-sort
  evaluate!(grammar, new_population, args...)
  sort!(new_population)

  # it's possible that we might have added too many individuals, so trim down if necessary
  while length(new_population) > length(population)
    pop!(new_population)
  end

  return new_population
end

# stateful iterator that keeps track of its current position, wraps the position
# when the maximum length is reached, and emits an exception when the maximum
# number of wraps occurs
type GenomeIterator
  #consts
  size::Int64
  maxwraps::Int64

  #states
  i::Int64
  wraps::Int64
end

function GenomeIterator(size::Int64, maxwraps::Int64;
                        i::Int64=0, wraps::Int64=0)
  return GenomeIterator(size, maxwraps, i, wraps)
end

function Base.consume(pos::GenomeIterator)
  pos.i += 1
  if pos.i > pos.size
    pos.wraps += 1
    pos.i = 1
  end
  if pos.wraps > pos.maxwraps
    throw(MaxWrapException())
  end
  return pos.i
end

function transform(grammar::Grammar, ind::Individual; maxwraps=2)
  pos = GenomeIterator(length(ind), maxwraps)
  value = transform(grammar, grammar.rules[:start], ind, pos)
  return value
end

function transform(grammar::Grammar, rule::OrRule, ind::Individual, pos::GenomeIterator)
  idx = (ind[consume(pos)] % length(rule.values))+1
  value = transform(grammar, rule.values[idx], ind, pos)

  if rule.action !== nothing
    value = rule.action(value)
  end

  return value
end

function transform(grammar::Grammar, rule::RangeRule, ind::Individual, pos::GenomeIterator)
  value = (ind[consume(pos)] % length(rule.range))+rule.range.start

  if rule.action !== nothing
    value = rule.action(value)
  end

  return value
end

function transform(grammar::Grammar, rule::ReferencedRule, ind::Individual, pos::GenomeIterator)
  return transform(grammar, grammar.rules[rule.symbol], ind, pos)
end

function transform(grammar::Grammar, rule::Terminal, ind::Individual, pos::GenomeIterator)
  return rule.value
end

function transform(grammar::Grammar, rule::AndRule, ind::Individual, pos::GenomeIterator)
  values = [transform(grammar, subrule, ind, pos) for subrule in rule.values]

  if rule.action !== nothing
    values = rule.action(values)
  end

  return values
end

function transform(grammar::Grammar, sym::Symbol, ind::Individual, pos::GenomeIterator)
  return sym
end

function transform(grammar::Grammar, q::QuoteNode, ind::Individual, pos::GenomeIterator)
  return q.value
end

function transform(grammar::Grammar, rule::ExprRule, ind::Individual, pos::GenomeIterator)
  args = [transform(grammar, arg, ind, pos) for arg in rule.args]
  return Expr(args...)
end

# It's very unlikely these two methods will be useful -- the maximum size of the genome is arbritrarily high, so
# you'll likely end up with mostly large numbers
# function transform(grammar::Grammar, rule::ZeroOrMoreRule, ind::Individual, pos::GenomeIterator)
#   # genome value gives number of time to repeat
#   reps = ind[consume(pos)]

#   # invoke given rule reps times
#   values = [transform(grammar, rule.rule, ind, pos) for i=1:reps]

#   if rule.action !== nothing
#     values = rule.action(values)
#   end

#   return values
# end

# function transform(grammar::Grammar, rule::OneOrMoreRule, ind::Individual, pos::GenomeIterator)
#   # genome value gives number of time to repeat
#   reps = ind[consume(pos)]

#   # enforce that it's at least one
#   if reps == 0
#     reps = 1
#   end

#   # invoke given rule reps times
#   values = [transform(grammar, rule.value, ind, pos) for i=1:reps]

#   if rule.action !== nothing
#     values = rule.action(values)
#   end

#   return values
# end

function transform(grammar::Grammar, rule::RepeatedRule, ind::Individual, pos::GenomeIterator)
  # genome value gives number of time to repeat
  reps = ind[consume(pos)]
  range = (rule.range.stop - rule.range.start)
  reps = (reps % range) + rule.range.start

  # invoke given rule reps times
  values = [transform(grammar, rule.value, ind, pos) for i=1:reps]

  if rule.action !== nothing
    values = rule.action(values)
  end

  return values
end

end # module
