from conan import ConanFile
# from conan.tools.cmake import cmake_layout
from conan.tools.files import copy
import os

class MyProjectConan(ConanFile):
    # name = "myproject"
    # version = "0.1"

    settings = "os", "compiler", "build_type", "arch"

    # 生成器
    generators = "CMakeToolchain", "CMakeDeps"

    # options = {"shared": [True, False]}

    def requirements(self):
        self.requires("boost/1.84.0", options={"header_only": True})

    def layout(self):
        # cmake_layout(self)
        # self.folders.build = os.path.join("build", str(self.settings.build_type))
        self.folders.build = ""
        self.folders.generators = os.path.join(self.folders.build, "generators")
        self.cpp.build.bindirs = ["bin"]
        self.cpp.build.libdirs = ["lib"]

    def generate(self):
        # if not self.options.shared:
        #     return
        build_bin = os.path.join(self.build_folder, "bin")
        os.makedirs(build_bin, exist_ok=True)
        for dep in self.dependencies.values():
            for shared_lib in dep.cpp_info.bindirs:
                print(">>>")
                print(">>>", shared_lib)
                print(">>>")
                copy(self, "*.dll", shared_lib, build_bin)
                copy(self, "*.so", shared_lib, build_bin)
                copy(self, "*.dylib", shared_lib, build_bin)
