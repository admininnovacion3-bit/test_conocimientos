import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// URL y clave PÚBLICA de Supabase se leen de local.properties (NO se suben a git).
// La publishable key (antes "anon key") es pública por diseño: la seguridad la imponen las políticas RLS.
// La secret key NUNCA debe ir aquí: un APK se puede descompilar.
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun prop(vararg nombres: String) =
    "\"${nombres.firstNotNullOfOrNull { localProps.getProperty(it) } ?: ""}\""

android {
    namespace = "com.dji.myapplication"
    compileSdk {
        version = release(37)
    }

    defaultConfig {
        applicationId = "com.dji.myapplication"
        minSdk = 31
        targetSdk = 37
        versionCode = 1
        versionName = "1.0"

        buildConfigField("String", "SUPABASE_URL", prop("SUPABASE_URL"))
        buildConfigField("String", "SUPABASE_ANON_KEY", prop("SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY"))
    }

    buildTypes {
        release {
            optimization {
                enable = true
                packageScope = setOf("androidx.**", "kotlin.**", "kotlinx.**")
            }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)

    implementation(platform(libs.supabase.bom))
    implementation(libs.supabase.auth)
    implementation(libs.supabase.postgrest)
    implementation(libs.supabase.functions)
    implementation(libs.ktor.client.okhttp)

    // Pruebas unitarias en la JVM (app/src/test): ./gradlew :app:testDebugUnitTest
    testImplementation(libs.junit)
}
