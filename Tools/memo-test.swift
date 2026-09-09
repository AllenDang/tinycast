import Foundation

@main
struct MemoTests {
    static func main() {
        let memo = Memo<String, Int?>()
        var builds = 0
        func build() -> Int? {
            builds += 1
            return nil
        }
        precondition(memo.value(for: "a", build: build) == nil)
        precondition(memo.value(for: "a", build: build) == nil)
        precondition(builds == 1, "nil results must be cached")
        let sameCache = memo
        _ = sameCache.value(for: "a", build: build)
        precondition(builds == 1, "a view cache must retain its reference without a State write")
        _ = memo.value(for: "b", build: build)
        precondition(builds == 2, "a changed dependency must invalidate")
        _ = memo.value(for: "a", build: build)
        precondition(builds == 3, "the cache stays bounded to one key")
        let independent = Memo<String, Int?>()
        _ = independent.value(for: "a", build: build)
        precondition(builds == 4, "independent caches must not share state")
        print("PASS  memo reuse, nil caching, invalidation, bounded retention and isolation")
    }
}
