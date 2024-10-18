import logging
from pprint import pprint
from xmlrpc.server import SimpleXMLRPCRequestHandler, SimpleXMLRPCServer


class RequestHandler(SimpleXMLRPCRequestHandler):
    rpc_paths = ()


class Directory(object):
    """A fake directory implementation to allow code in the integration
    tests to be properly exercised.
    """

    def store_s3(self, location, usage):
        print("store_s3")
        pprint(location)
        pprint(usage)

    def list_s3_users(self, location, storage_resource_group_filter):
        print("list_s3_users with", location, storage_resource_group_filter)
        return {
            "fc": {
                "location": "rzob",
                "storage_resource_group": "services",
                "display_name": "FC user",
                "access_key": "ubbsAFsG",
                "secret_key": None,
                "deletion": {"deadline": "", "stages": []},
            },
            "services:sometest": {
                "location": "rzob",
                "storage_resource_group": "services",
                "display_name": "test modified",
                "access_key": "dnDlid0jyRs1sK9vEOGV",
                "secret_key": "VqBfxCqupucBSjo7ksDcf4K6vhgsIdGKnL0ielLi",
                # "secret_key": None,
                "deletion": {"deadline": "", "stages": ["soft"]},
            },
        }

    def update_s3_users(self, users_report):
        print("update_s3_users")
        pprint(users_report)


logging.basicConfig(level=logging.DEBUG)
# Create server
with SimpleXMLRPCServer(
    ("0.0.0.0", 2342), requestHandler=RequestHandler, allow_none=True
) as server:
    server.register_introspection_functions()
    server.register_instance(Directory())

    # Run the server's main loop
    server.serve_forever()
