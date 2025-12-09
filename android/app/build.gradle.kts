plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // Firebase
}

android {
    // 👇 عدّل إلى حزمة تطبيقك الفعلية (وطابقها مع google-services.json)
    namespace = "com.darvoo.owner"

    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.darvoo.owner" // 👈 طابقها مع Firebase
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Java 17 + تفعيل desugaring
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            // مبدئيًا استخدم توقيع debug؛ بدّله لاحقًا بتوقيع الإصدار
            signingConfig = signingConfigs.getByName("debug")
        }
        debug { }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ الحل الجذري: حدّث desugar_jdk_libs إلى 2.1.4 أو أحدث
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // (اختياري) Firebase BoM وبعض الخدمات
    implementation(platform("com.google.firebase:firebase-bom:34.1.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-auth")
    // لا حاجة لإضافة messaging يدويًا لأن FlutterFire يسحبه تلقائيًا
}
