require 'fileutils'
require 'open3'
require 'pathname'
require 'rbconfig'
require 'tempfile'

require_relative 'strum-evaluate.rb'


# Metadata of the program
PROGRAM_NAME = "strum-pattern"
PROGRAM_VERSION = "0.1.0"


# Add .exe for executable on Windows
def executable_name(name)
  (RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/) ? (name + ".exe") : name
end

# Check whether a command exists or not.
def command?(name)
  [executable_name(name),
   *ENV['PATH'].split(File::PATH_SEPARATOR).map {
      |p| File.join(p, executable_name(name))
    }
  ].find {|f| File.executable?(f)}
end


# Trade-off: shell out to LilyPond instead of embedding a rendering layer here.
# This keeps the tool small, but makes output depend on an external compiler.
if not command?("lilypond") then
    STDERR.puts "No LilyPond on the system"
    exit 1
end

# Template for the usage for the program.
usage = <<END_USAGE
#{PROGRAM_NAME} [option] [pattern] ...

Strums:

* D: downward strum
* U: upward strum
* R: rest
* _: extend from the last beat

Pattern Examples:

* D-D-D-D
* D-D-DU-DU
* RU-RU-RU-RU (rest)
* D-D-D-_ (half note)
* D_DU-DU-D_DU-DU (sixteenth note)
* D-DU-_U-DU (tie)
* D_U-D_U-D_U-D_U (swing)

Each pattern here belongs to a measure in music
END_USAGE

generate_code = false
diagram_size = 60
output_file_name = ""

# Parse the command-line parameters.
while ARGV.length > 0 do
  if "-v" == ARGV[0] or "--version" == ARGV[0]
    puts PROGRAM_VERSION
    exit 0
  elsif "-h" == ARGV[0] or "--help" == ARGV[0]
    puts usage
    exit 0
  elsif "-o" == ARGV[0] or "--output" == ARGV[0]
    ARGV.shift
    if 0 == ARGV.length
      STDERR.puts "No file name specified"
      exit 1
    end

    output_file_name = ARGV[0]
    ARGV.shift
  elsif "-ly" == ARGV[0] or "--lilypond" == ARGV[0]
    generate_code = true
    ARGV.shift  # Discard a parameter.
  elsif "-s" == ARGV[0] or "--size" == ARGV[0]
    ARGV.shift
    if 0 == ARGV.length
      STDERR.puts "No size specified"
      exit 1
    end

    diagram_size = ARGV[0].to_i
    if diagram_size <= 0
      STDERR.puts "Invalid size: #{diagram_size}"
      exit 1
    end
    ARGV.shift
  else
    break
  end
end

if ARGV.length < 1
  STDERR.puts "#{usage}"
  exit 1
end

measures = ARGV

piece = []
result = "s1"

begin
  piece = strum_parse(measures)
  result = strum_evaluate(piece)
rescue => e
    STDERR.puts "#{e.message}"
    exit 1
end

lilypond_preamble = <<END_LILYPOND_PREAMBLE
\\version "2.22.1"

#(set-global-staff-size #{diagram_size})

#(ly:set-option 'crop #t)
END_LILYPOND_PREAMBLE

# Trade-off: generate LilyPond source directly as a string instead of building
# a separate output IR. Simpler pipeline, tighter coupling to LilyPond syntax.
lilypond_strum_code = <<END_LILYPOND_STRUM_CODE
#{lilypond_preamble}
\\score {
  <<
  \\new Voice \\with {
    \\consists "Pitch_squash_engraver"
  } {
    \\improvisationOn
    \\time #{time_signature piece}
    #{result}
  }
  >>

  \\layout {}
}
END_LILYPOND_STRUM_CODE

if generate_code
  if "" != output_file_name
    File.open(output_file_name, "w") do |file|
      file.write lilypond_strum_code
    end
  else
    puts lilypond_strum_code
  end

  exit 0
end

# Trade-off: use a temporary script as the boundary between parsing and rendering.
# Less elegant than an in-process API, but portable and easy to debug.
lilypond_script = Tempfile.new([ 'lilypond-', '.ly' ])

lilypond_script.write lilypond_strum_code
lilypond_script.close

lilypond_script_path = lilypond_script.path

file_dirname = File.dirname(lilypond_script_path)
file_basename_no_ext = File.basename(lilypond_script_path, '.*')

lilypond_pdf_path = File.join(file_dirname, "#{file_basename_no_ext}.pdf")
lilypond_cropped_pdf_path = File.join(file_dirname, "#{file_basename_no_ext}.cropped.pdf")
lilypond_cropped_png_path = File.join(file_dirname, "#{file_basename_no_ext}.cropped.png")

lilypond_command = "lilypond -o #{file_dirname} #{lilypond_script_path}"

stdout, stderr, status = Open3.capture3(lilypond_command)

if "" == output_file_name
  output_file_name = "#{measures.join("_")}.png"
end

if status.success?
  FileUtils.cp(lilypond_cropped_png_path, File.join(Dir.pwd, output_file_name))
else
  STDERR.puts stderr
end

lilypond_script.unlink
File.unlink lilypond_pdf_path if File.exists? lilypond_pdf_path
File.unlink lilypond_cropped_pdf_path if File.exists? lilypond_cropped_pdf_path
File.unlink lilypond_cropped_png_path if File.exists? lilypond_cropped_png_path

exit 1 if not status.success?