import gleeunit
import kairos

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_name_test() {
  assert kairos.package_name() == "kairos"
}
