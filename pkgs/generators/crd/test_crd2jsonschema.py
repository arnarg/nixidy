import sys
import os
import unittest

sys.path.append(os.path.dirname(__file__))

from crd2jsonschema import gen_attr_name


class TestGenAttrName(unittest.TestCase):
    def test_simple_plural(self):
        self.assertEqual(gen_attr_name("Deployment", "deployments", ""), "deployments")

    def test_camel_case_plural(self):
        self.assertEqual(
            gen_attr_name("NetworkPolicy", "networkpolicies", ""), "networkPolicies"
        )

    def test_name_prefix(self):
        self.assertEqual(
            gen_attr_name("NetworkPolicy", "networkpolicies", "cilium"),
            "ciliumNetworkPolicies",
        )

    def test_leading_acronym(self):
        self.assertEqual(gen_attr_name("HTTPRoute", "httproutes", ""), "httpRoutes")

    def test_leading_acronym_prefix(self):
        self.assertEqual(gen_attr_name("HTTPRoute", "httproutes", "gateway"), "gatewayHTTPRoutes")

if __name__ == "__main__":
    unittest.main()
