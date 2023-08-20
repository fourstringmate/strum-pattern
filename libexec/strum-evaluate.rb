class Strum
    attr_reader :level, :direction
    attr_accessor :tie

    def initialize(level, direction)
        @level = level
        @direction = direction
        @tie = false
    end

    def +(other)
        strum = nil

        if :extension != other.direction then
            return strum
        end

        if :dotted_half == @level then
            if :quarter == other.level then
                strum = Strum.new(:whole, @direction)
            end
        elsif :half == @level then
            if :half == other.level then
                strum = Strum.new(:whole, @direction)
            elsif :quarter == other.level then
                strum = Strum.new(:dotted_half, @direction)
            end
        elsif :dotted_quarter == @level then
            if :eighth == other.level then
                strum = Strum.new(:half, @direction)
            end
        elsif :quarter == @level then
            if :quarter == other.level then
                strum = Strum.new(:half, @direction)
            elsif :eighth == other.level then
                strum = Strum.new(:dotted_quarter, @direction)
            end
        elsif :eighth == @level then
            if :eighth == other.level then
                strum = Strum.new(:quarter, @direction)
            elsif :sixteenth == other.level then
                strum = Strum.new(:dotted_eighth, @direction)
            end
        elsif :sixteenth == @level then
            if :sixteenth == other.level then
                strum = Strum.new(:eighth, @direction)
            end
        elsif :two_triplet == @level then
            if :triplet == other.level then
                strum = Strum.new(:quarter, @direction)
            end
        elsif :triplet == @level then
            if :triplet == other.level then
                strum = Strum.new(:two_triplet, @direction)
            end
        end

        strum
    end

    def to_s
        if :rest == @direction
            "Rest for #{@level} note"
        elsif :extension == @direction
            "Extend for #{@level} note"
        else
            "Strum #{@direction} for #{@level} note"
        end
    end
end

# Lex a strum pattern.
def lex_measure(measure)
    note_strings = []

    note_string = ""
    i = 0
    while i < measure.length do
        if "-" == measure[i]
            # Append current measure to the measures.
            note_strings << note_string
            # Create a new measure.
            note_string = ""
        elsif measure[i] =~ /[DdUuRr\_]/
            note_string += measure[i]
        else
            raise "Unknown beat string at #{i+1}: -->#{measure[i]}<--"
        end

        i += 1
    end

    # Append the last note.
    note_strings << note_string

    note_strings
end

def parse_note(note_string, level)
    notes = []

    note_string.each_char.with_index do |c, i|
        if "D" == c
            notes << Strum.new(level, :downward)
        elsif "U" == c
            notes << Strum.new(level, :upward)
        elsif "R" == c
            notes << Strum.new(level, :rest)
        elsif "_" == c
            notes << Strum.new(level, :extension)
        else
            raise "Unknown note: -->#{c}<--"
        end
    end

    notes
end

# Parse a strum pattern.
def parse_measure(note_strings)
    measure = []

    note_strings.each do |ns|
        if 1 == ns.length
            level = :quarter
        elsif 2 == ns.length
            level = :eighth
        elsif 3 == ns.length
            level = :triplet
        elsif 4 == ns.length
            level = :sixteenth
        elsif 6 == ns.length
            level = :sextuplet
        else
            raise "Invalid notes: -->#{ns}<--"
        end 

        measure << parse_note(ns, level)
    end

    measure
end

def strum_parse(measures)
    piece = []

    measures.each do |measure|
        piece << parse_measure(lex_measure(measure))
    end

    i = 0
    while i < piece.length do
        j = 0
        while j < piece[i].length do
            k = 0
            while k < piece[i][j].length do
                if not piece[i][j][k+1].nil? then
                    if :extension == piece[i][j][k+1].direction then
                        strum = piece[i][j][k] + piece[i][j][k+1]
                        if not strum.nil? then
                            piece[i][j][k] = strum
                            piece[i][j].delete_at(k+1)
                            next  # Check if more note(s) to merge.
                        else
                            piece[i][j][k].tie = true
                        end
                    end
                elsif (not piece[i][j+1].nil?) and (not piece[i][j+1][0].nil?) then
                    if :extension == piece[i][j+1][0].direction then
                        strum = piece[i][j][k] + piece[i][j+1][0]
                        if not strum.nil? and piece[i][j+1].all? {|n| :extension == n.direction } then
                            piece[i][j][k] = strum
                            piece[i][j+1].delete_at(0)
                            if piece[i][j+1].empty? then
                                piece[i].delete_at(j+1)
                            end
                            next # Check if more note(s) to merge.
                        else
                            piece[i][j][k].tie = true
                        end
                    end
                end

                k += 1
            end

            j += 1
        end

        i += 1
    end

    piece
end

def strum_evaluate(piece)
    result = ""

    piece.each.with_index do |measure, i|
        measure.each.with_index do |beat, j|
            beat.each.with_index do |note, k|
                if :two_triplet == note.level or :triplet == note.level then
                    if 0 == k then
                        result += "\\tuplet 3/1 { "
                    end
                end

                if :rest == note.direction then
                    result += "r"
                else
                    result += "c"
                end

                if :whole == note.level then
                    result += "1"
                elsif :dotted_half == note.level then
                    result += "2."
                elsif :half == note.level then
                    result += "2"
                elsif :dotted_quarter == note.level then
                    result += "4."
                elsif :quarter == note.level then
                    result += "4"
                elsif :dotted_eighth == note.level then
                    result += "8."
                elsif :eighth == note.level then
                    result += "8"
                elsif :sixteenth == note.level then
                    result += "16"
                elsif :two_triplet == note.level then
                    result += "4"
                elsif :triplet == note.level then
                    result += "8"
                end

                result += "~" if note.tie

                result += "\\downbow" if :downward == note.direction
                result += "\\upbow" if :upward == note.direction

                result += " " unless k >= beat.length - 1

                if :two_triplet == note.level or :triplet == note.level then
                    if k == beat.length - 1 then
                        result += " }"
                    end
                end
            end

            result += " " unless j >= measure.length - 1
        end

        result += " " unless i >= piece.length - 1
    end

    result
end

def time_signature(piece)
    t = 0
    piece[0].each do |beat|
        beat.each do |note|
            if :whole == note.level then
                t += 4
            elsif :dotted_half == note.level then
                t += 3
            elsif :half == note.level then
                t += 2
            elsif :dotted_quarter == note.level then
                t += 1.5
            elsif :quarter == note.level then
                t += 1
            elsif :dotted_eighth == note.level then
                t += 0.75
            elsif :eighth == note.level then
                t += 0.5
            elsif :sixteenth == note.level then
                t += 0.25
            elsif :two_triplet == note.level then
                t += 0.66
            elsif :triplet == note.level then
                t += 0.33
            end
        end
    end

    # FIXME: Check 6/8 and other less common time signature.
    "#{t.ceil.to_i.to_s}/4"
end
