require 'xcodeproj'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
target = project.targets.first
group = project.main_group['Runner']
['CallKitService.swift', 'SocketKeepaliveService.swift'].each do |file|
  unless group.files.any? { |f| f.path == file }
    ref = group.new_file(file)
    target.source_build_phase.add_file_reference(ref)
    puts "Registered #{file}"
  else
    puts "Already registered: #{file}"
  end
end
project.save
