/*
 * Copyright 2014-2015 CyberVision, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#define HC_SHORTHAND
#import <OCHamcrest/OCHamcrest.h>

#define MOCKITO_SHORTHAND
#import <OCMockito/OCMockito.h>

#import <XCTest/XCTest.h>
#import "DefaultOperationHttpChannel.h"
#import "TransportProtocolIdHolder.h"
#import "KeyUtils.h"
#import "GenericTransportInfo.h"
#import "TestsHelper.h"

static NSDictionary *SUPPORTED_TYPES;

#pragma mark DefaultOperationHttpChannelFake

@interface DefaultOperationHttpChannelFake : DefaultOperationHttpChannel

@property (nonatomic) NSInteger wantedNumberOfInvocations;

- (instancetype)initWithClient:(AbstractKaaClient *)client
                         state:(id<KaaClientState>)state
               failoverManager:(id<FailoverManager>)manager
  wantedNumberOfInvocations:(NSInteger)wantedNumberOfInvocations;
@end

@implementation DefaultOperationHttpChannelFake

- (instancetype)initWithClient:(AbstractKaaClient *)client
                         state:(id<KaaClientState>)state
               failoverManager:(id<FailoverManager>)manager
  wantedNumberOfInvocations:(NSInteger)wantedNumberOfInvocations {
    self = [super initWithClient:client state:state failoverManager:manager];
    self.wantedNumberOfInvocations = wantedNumberOfInvocations;
    return self;
}

- (NSOperationQueue *) createExecutor {
    return [super createExecutor];
}

@end

#pragma mark DefaultOperationHttpChannelTest

@interface DefaultOperationHttpChannelTest : XCTestCase

@end

@implementation DefaultOperationHttpChannelTest

- (void)setUp {
    SUPPORTED_TYPES =
    [NSDictionary dictionaryWithObjects:@[[NSNumber numberWithInt:CHANNEL_DIRECTION_UP], [NSNumber numberWithInt:CHANNEL_DIRECTION_UP]] forKeys:@[[NSNumber numberWithInt:TRANSPORT_TYPE_EVENT], [NSNumber numberWithInt:TRANSPORT_TYPE_LOGGING]]];
}


- (void)testChannelGetters {
    AbstractKaaClient *client = mock([AbstractKaaClient class]);
    id <KaaClientState> state = mockProtocol(@protocol(KaaClientState));
    id <FailoverManager> manager = mockProtocol(@protocol(FailoverManager));
    id <KaaDataChannel> channel = [[DefaultOperationHttpChannel alloc] initWithClient:client state:state failoverManager:manager];
    
    XCTAssertEqualObjects(SUPPORTED_TYPES, [channel getSupportedTransportTypes]);
    XCTAssertEqualObjects([TransportProtocolIdHolder HTTPTransportID], [channel getTransportProtocolId]);
    XCTAssertEqualObjects(@"default_operations_http_channel", [channel getId]);
}

- (void)testChannelSync {
    id <KaaChannelManager> manager = mockProtocol(@protocol(KaaChannelManager));
    AbstractHttpClient *httpClient = mock([AbstractHttpClient class]);
    id <FailoverManager> failoverManager = mockProtocol(@protocol(FailoverManager));
    
    int32_t five = 5;
    NSMutableData *data = [NSMutableData dataWithBytes:&five length:sizeof(five)];
    [data appendBytes:&five length:sizeof(five)];
    [data appendBytes:&five length:sizeof(five)];
    
    [given([httpClient executeHttpRequest:anything() entity:anything() verifyResponse:anything()]) willReturn:data];
    
    [KeyUtils generateKeyPair];
    AbstractKaaClient *client = mock([AbstractKaaClient class]);
    [given([client createHttpClientWithURLString:anything() privateKeyRef:[KeyUtils getPrivateKeyRef] publicKeyRef:[KeyUtils getPublicKeyRef] remoteKey:anything()]) willReturn:httpClient];
    [given([client getChannelManager]) willReturn:manager];
    
    id <KaaClientState> state = mockProtocol(@protocol(KaaClientState));
    id <KaaDataMultiplexer> multiplexer = mockProtocol(@protocol(KaaDataMultiplexer));
    id <KaaDataDemultiplexer> demultiplexer = mockProtocol(@protocol(KaaDataDemultiplexer));
    DefaultOperationHttpChannelFake *channel = [[DefaultOperationHttpChannelFake alloc] initWithClient:client state:state failoverManager:failoverManager wantedNumberOfInvocations:2];
    
    id <TransportConnectionInfo> server = [self createTestServerInfoWithServerType:SERVER_BOOTSTRAP transportProtocolId:[TransportProtocolIdHolder TCPTransportID] host:@"localhost" port:9889 publicKey:[KeyUtils getPublicKey]];
    [channel setServer:server];
    
    [channel sync:TRANSPORT_TYPE_EVENT];
    [channel setDemultiplexer:demultiplexer];
    [channel setDemultiplexer:nil];
    [channel sync:TRANSPORT_TYPE_EVENT];
    [channel setMultiplexer:multiplexer];
    [channel setMultiplexer:nil];
    [channel sync:TRANSPORT_TYPE_BOOTSTRAP];
    [channel sync:TRANSPORT_TYPE_EVENT];
    
    [NSThread sleepForTimeInterval:1];
    [verifyCount([channel getMultiplexer], times(channel.wantedNumberOfInvocations)) compileRequest:anything()];
    [verifyCount([channel getDemultiplexer], times(channel.wantedNumberOfInvocations)) processResponse:anything()];
}

- (void)testShutDown {
    id <KaaChannelManager> manager = mockProtocol(@protocol(KaaChannelManager));
    AbstractHttpClient *httpClient = mock([AbstractHttpClient class]);
    id <FailoverManager> failoverManager = mockProtocol(@protocol(FailoverManager));
    NSException *excption = [[NSException alloc] initWithName:@"Exception" reason:@"Exception raised" userInfo:nil];
    [given([httpClient executeHttpRequest:anything() entity:anything() verifyResponse:anything()]) willThrow:excption];
    
    AbstractKaaClient *client = mock([AbstractKaaClient class]);
    [given([client createHttpClientWithURLString:anything() privateKeyRef:[KeyUtils getPrivateKeyRef] publicKeyRef:[KeyUtils getPublicKeyRef] remoteKey:anything()]) willReturn:httpClient];
    [given([client getChannelManager]) willReturn:manager];
    
    id <KaaClientState> state = mockProtocol(@protocol(KaaClientState));
    id <KaaDataMultiplexer> multiplexer = mockProtocol(@protocol(KaaDataMultiplexer));
    id <KaaDataDemultiplexer> demultiplexer = mockProtocol(@protocol(KaaDataDemultiplexer));
    DefaultOperationHttpChannelFake *channel = [[DefaultOperationHttpChannelFake alloc] initWithClient:client state:state failoverManager:failoverManager wantedNumberOfInvocations:0];
    [channel setMultiplexer:multiplexer];
    [channel setDemultiplexer:demultiplexer];
    [channel shutdown];
    
    id <TransportConnectionInfo> server = [self createTestServerInfoWithServerType:SERVER_BOOTSTRAP transportProtocolId:[TransportProtocolIdHolder TCPTransportID] host:@"localhost" port:9889 publicKey:[KeyUtils getPublicKey]];
    [channel setServer:server];
    
    [channel sync:TRANSPORT_TYPE_BOOTSTRAP];
    [channel syncAll];
    
    int32_t five = 5;
    NSMutableData *data = [NSMutableData dataWithBytes:&five length:sizeof(five)];
    [data appendBytes:&five length:sizeof(five)];
    [data appendBytes:&five length:sizeof(five)];

    [NSThread sleepForTimeInterval:1];
    [verifyCount([channel getDemultiplexer], times(channel.wantedNumberOfInvocations)) processResponse:data];
    [verifyCount([channel getMultiplexer], times(channel.wantedNumberOfInvocations)) compileRequest:anything()];
}


#pragma mark - Supporting methods 

- (id<TransportConnectionInfo>)createTestServerInfoWithServerType:(ServerType)serverType transportProtocolId:(TransportProtocolId *)TPid host:(NSString *)host port:(uint32_t)port publicKey:(NSData *)publicKey {
    ProtocolMetaData *md = [[ProtocolMetaData alloc] init];
    md = [TestsHelper buildMetaDataWithTransportProtocolId:TPid host:host port:port publicKey:publicKey];
    return  [[GenericTransportInfo alloc] initWithServerType:serverType meta:md];
}

@end
