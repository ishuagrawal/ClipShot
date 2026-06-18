#!/usr/bin/env ruby
# Registers Swift source files into the classic project.pbxproj (no filesystem-
# synchronized groups). Usage:
#   ruby Scripts/add-sources.rb <TargetName> <path/relative/to/root.swift> [more...]
# Paths are project-root-relative; groups mirror the directory structure.

require 'xcodeproj'

target_name = ARGV.shift
files = ARGV
abort("usage: add-sources.rb <Target> <file.swift> [...]") if target_name.nil? || files.empty?

root = File.expand_path(File.join(__dir__, '..'))
project = Xcodeproj::Project.open(File.join(root, 'ClipShot.xcodeproj'))
target = project.targets.find { |t| t.name == target_name }
abort("target not found: #{target_name}") unless target

def group_for(project, components)
  group = project.main_group
  components.each do |component|
    child = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.path == component }
    child ||= group.new_group(component, component)
    group = child
  end
  group
end

files.each do |relpath|
  components = relpath.split('/')
  basename = components.pop
  group = group_for(project, components)

  ref = group.children.find { |c| c.respond_to?(:path) && c.path == basename }
  ref ||= group.new_reference(basename)

  already = target.source_build_phase.files_references.include?(ref)
  target.source_build_phase.add_file_reference(ref, true) unless already
  puts "#{already ? 'present' : 'added '} #{target_name}  #{relpath}"
end

project.save
