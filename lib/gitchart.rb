require 'rubygems'

require 'google_chart'
include GoogleChart

require 'grit'
include Grit

class GitChart
  def initialize(size = '1000x300', threed = true, repo = '.')
    begin
      @repo = Repo.new(repo)
    rescue
      raise "Could not initialize Grit instance."
    end
    @size = size
    @threed = threed
  end
  
  def run
    chart_authors
  end
  
  def chart_authors
    authors = {}
    @repo.commits.each do |c|
      if authors[c.author.to_s]
        authors[c.author.to_s] += 1
      else
        authors[c.author.to_s] = 1
      end
    end
    PieChart.new(@size, 'Repository Authors', @threed) do |pc|
      authors.each do |a, num|
        pc.data a, num
      end
      puts pc.to_url
    end
  end
end

g = GitChart.new
g.run