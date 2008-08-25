=begin
Copyright (c) 2008 Hans Engel
See the file LICENSE for licensing details.
=end

require 'ftools'
require 'tempfile'

require 'platform'
require 'google_chart'
include GoogleChart
require 'grit'
include Grit

class GitChart
  def initialize(size = '1000x300', threed = true, repo = '.', branch = 'master')
    begin
      @repo = Repo.new(repo)
    rescue
      raise "Could not initialize Grit instance."
    end
    @size = size
    @threed = threed
    @branch = branch
    @files = 0
    if repo == '.'
      rpath = Dir.getwd
    else
      rpath = repo
    end
    @html = <<EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
	"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
	<head profile="http://purl.org/uF/2008/03">
		<meta http-equiv="Content-type" content="text/html; charset=UTF-8" />
		<style type="text/css">
		  * { margin: 0; padding: 0; }
		  body { width: 1000px; margin: 50px auto; overflow: auto; text-align: center; font-size: 13px; }
		  h1 { font-weight: normal; font-size: 20px; }
		  table { border: none; margin: 20px auto; width: 500px; }
		  tr { border: none; }
		  td { border: none; padding: 7px; }
		  td.key { background-color: #c7e4e5; width: 145px; font-weight: bold; font-size: 11px; }
		</style>
		<title>gitchart output</title>
	</head>
	<body>
	  <h1>Git Repository Stats</h1>
	  <p>These stats were generated by <a href="http://github.com/hans/git-chart"><code>git-chart</code></a>.
    <table cellpadding="0" cellspacing="0">
      <tr>
        <td class="key">repository location:</td>
        <td>#{rpath}</td>
      </tr>
      <tr>
        <td class="key">generated on:</td>
        <td>#{Time.now.to_s}</td>
      </tr>
    </table>
    
EOF
  end
  
  def run
    puts "Generating chart data . . ."
    puts "This may take a while, depending on the size of your repository."
    begin
      @commits = @repo.commits_since @branch
    rescue SystemStackError
      puts "Uh oh, your repository is humongous. We're going to have to only grab stats for the last several hundred."
      puts "How many commits should be graphed? (750 is probably as far as you can get). "
      amt = gets
      @commits = @repo.commits @branch, amt.strip.to_i
    end
    chart_authors
    chart_commits :bar
    chart_commits :line
    chart_hours
    chart_extensions
    chart_bytes
    chart_awesomeness
    output
  end
  
  def chart_authors
    generating_chart 'Repository Authors'
    authors = {}
    @commits.each do |c|
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
      @html += "<img src='#{pc.to_url}' alt='Repository Authors' /><br/>"
    end
  end
  
  def chart_commits(type)
    generating_chart 'Commit Frequency'
    weeks = Array.new 53, 0
    @commits.each do |c|
      time = Time.parse c.committed_date.to_s
      week = time.strftime '%U'
      weeks[week.to_i] ||= 0
      weeks[week.to_i] += 1
    end
    case type
    when :bar:
      BarChart.new(@size, 'Commit Frequency', :vertical, @threed) do |bc|
        bc.data 'Commits', weeks
        bc.axis :y, { :range => [0, weeks.max] }
        @html += "<img src='#{bc.to_url}' alt='Commit Frequency' /><br/>"
      end
    when :line:
      weeks.pop while weeks.last.zero?
      LineChart.new @size, 'Commit Frequency' do |lc|
        lc.data 'Commits', weeks
        lc.axis :y, { :range => [0, weeks.max] }
        @html += "<img src='#{lc.to_url}' alt='Commit Frequency' /><br/>"
      end
    end
  end
  
  def chart_hours
    generating_chart 'Commit Hours'
    hours = Hash.new
    @commits.each do |c|
      date = Time.parse c.committed_date.to_s
      hour = date.strftime '%H'
      hours[hour.to_i] ||= 0
      hours[hour.to_i] += 1
    end
    PieChart.new(@size, 'Commit Hours', @threed) do |pc|
      hours.each do |hr, num|
        pc.data hr.to_s + ':00 - ' + hr.to_s + ':59', num
      end
      @html += "<img src='#{pc.to_url}' alt='Commit Hours' /><br/>"
    end
  end
  
  def chart_extensions
    generating_chart 'Popular Extensions'
    @extensions = {}
    @tree = @commits.first.tree
    extensions_add_tree @tree
    PieChart.new(@size, 'Popular Extensions', @threed) do |pc|
      @extensions.each do |ext, num|
        pc.data ext, num
      end
      @html += "<img src='#{pc.to_url}' alt='Popular Extensions' /><br/>"
    end
  end
  def extensions_add_tree(tree)
    tree.contents.each do |el|
      if Blob === el
        extensions_add_blob el
      elsif Tree === el
        extensions_add_tree el
      end
    end
  end
  def extensions_add_blob(el)
    ext = File.extname el.name
    if ext == ''
      @extensions['Other'] += 1 rescue @extensions['Other'] = 1
    else
      @extensions[ext] += 1 rescue @extensions[ext] = 1
    end
    @files += 1
  end
  
  def chart_bytes
    generating_chart 'Total Filesize'
    @bytes = Array.new
    @commits.each do |c|
      @bytes.push 0
      bytes_add_tree c.tree
    end
    @bytes = @bytes.reverse
    LineChart.new(@size, 'Total Filesize') do |lc|
      lc.data 'Bytes', @bytes
      lc.axis :y, { :range => [0, @bytes.max] }
      @html += "<img src='#{lc.to_url}' alt='Total Filesize' /><br/>"
    end
  end
  def bytes_add_tree(tree)
    tree.contents.each do |el|
      if Blob === el
        bytes_add_blob el
      elsif Tree === el
        bytes_add_tree el
      end
    end
  end
  def bytes_add_blob(blob)
    bytes = blob.size
    @bytes[-1] += bytes
  end
  
  def chart_awesomeness
    generating_chart 'Repository Awesomeness'
    @extensions['.rb'] ||= 0.1
    awesomeness = @files / @extensions['.rb']
    awesomeness = ( awesomeness * 100 ).round / 100.0
    awesomeness = 0.1 if @extensions['.rb'] == 0.1
    url = "http://chart.apis.google.com/chart?cht=gom&chtt=Repository+Awesomeness&chs=#{@size}&chl=#{awesomeness}%25&chd=t:#{awesomeness}"
    @html += "<img src='#{url}' alt='Repository Awesomeness' /><br/><br/>"
  end
  
  def generating_chart(chart)
    puts "Generating chart '#{chart}' . . ."
  end
  
  def output
    @html += <<EOF
  </body>
</html>
EOF
    t = Tempfile.new 'gitchart-' + Time.now.to_i.to_s
    t.print @html
    t.flush
    f = t.path + '.html'
    File.move t.path, f
    case Platform::OS
    when :unix:
      if Platform::IMPL == :macosx
        `open #{f}`
      else
        `xdg-open #{f}`
      end
    when :win32:
      `start #{f}`
    end
  end
end