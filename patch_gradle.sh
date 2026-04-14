#!/bin/bash
# Append the fix to the bottom of android/build.gradle
cat >> android/build.gradle << 'GRADLE_EOF'

subprojects {
    afterEvaluate { project ->
        if (project.hasProperty('android') && project.name == 'contacts_service') {
            project.android {
                namespace = "com.baseflow.contacts_service"
            }
        }
    }
}
GRADLE_EOF
echo "✅ Gradle namespace patch applied."
