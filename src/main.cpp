#include <algorithm>
#include <boost/version.hpp>
#include <cstdlib>
#include <ctime>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <sstream>
#include <string>
#include <vector>

#include <json/json.h>
#include <json/version.h>

namespace demo {

int parse_count(int argc, char* argv[]) {
    const int kDefaultCount = 10;
    if (argc < 2) {
        return kDefaultCount;
    }

    std::istringstream input(argv[1]);
    int value = 0;
    if (!(input >> value) || value <= 0) {
        std::cout << "Invalid count: " << argv[1]
                  << ", fallback to default (" << kDefaultCount << ").\n";
        return kDefaultCount;
    }
    return value;
}

std::vector<int> build_data(int count) {
    std::vector<int> data(static_cast<std::size_t>(count), 0);
    for (int i = 0; i < count; ++i) {
        data[static_cast<std::size_t>(i)] = (i + 1) * (i + 1);
    }
    return data;
}

void print_now() {
    const std::time_t now = std::time(NULL);
    std::tm local_tm = *std::localtime(&now);
    std::cout << "Now: " << std::put_time(&local_tm, "%Y-%m-%d %H:%M:%S")
              << '\n';
}

void print_data(const std::vector<int>& data) {
    std::cout << "Data: ";
    for (std::size_t i = 0; i < data.size(); ++i) {
        std::cout << data[i];
        if (i + 1 != data.size()) {
            std::cout << ", ";
        }
    }
    std::cout << '\n';
}

}  // namespace demo

int main(int argc, char* argv[]) {
    std::cout << "=== cbuild-py demo ===\n";
    demo::print_now();

    const int count = demo::parse_count(argc, argv);
    const std::vector<int> data = demo::build_data(count);
    demo::print_data(data);

    const int sum = std::accumulate(data.begin(), data.end(), 0);
    const std::vector<int>::const_iterator max_it =
        std::max_element(data.begin(), data.end());
    const int max_value = (max_it != data.end()) ? *max_it : 0;

    std::cout << "Count: " << data.size() << '\n';
    std::cout << "Sum: " << sum << '\n';
    std::cout << "Max: " << max_value << '\n';

    Json::Value summary;
    summary["boost_version"] = BOOST_LIB_VERSION;
    summary["jsoncpp_version"] = JSONCPP_VERSION_STRING;
    summary["count"] = static_cast<Json::UInt64>(data.size());
    summary["sum"] = sum;
    summary["max"] = max_value;

    Json::StreamWriterBuilder writer;
    writer["indentation"] = "  ";
    std::cout << "Dependencies:\n" << Json::writeString(writer, summary) << '\n';
    std::cout << "Tip: pass a positive integer argument, e.g. ./application 5\n";

    return EXIT_SUCCESS;
}
