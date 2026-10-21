@0xc7869f1a4bd295ea;

struct Growing(T) {
  value @0 :T;
  next @1 :Growing(List(Box(T)));
}

struct Box(T) { value @0 :T; }

struct Pair(A, B) {
  left @0 :A;
  right @1 :B;
}

struct Tree(T) {
  value @0 :T;
  next @1 :Tree(Pair(T, T));
}

struct Uses {
  growing @0 :Growing(Text);
  tree @1 :Tree(Text);
}
