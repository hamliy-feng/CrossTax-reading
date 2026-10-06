"""Allowlisted model calls, preserving the existing NDJSON event contract."""
from __future__ import annotations
import json
import httpx
import server

DISCLAIMER='AI 可能会说错，请注意甄别。'


def finalize(text):
    return str(text or '').replace(DISCLAIMER,'').rstrip()+'\n\n'+DISCLAIMER


async def complete(messages,config,tools=None,timeout=100):
    provider,model,key=config
    if not key:
        raise RuntimeError('模型服务暂未配置')
    body={'model':model,'messages':messages,'stream':False}
    if tools:
        body.update(tools=tools,tool_choice='auto')
    async with httpx.AsyncClient(timeout=timeout) as client:
        r=await client.post(server.PROVIDERS[provider]['base']+'/chat/completions',json=body,headers={'Authorization':'Bearer '+key})
        if r.status_code!=200:
            raise RuntimeError('模型接口 HTTP '+str(r.status_code))
        data=r.json()
        if not data.get('choices'):
            raise RuntimeError('模型未返回内容')
        return data['choices'][0]['message'],data.get('usage',{})


async def stream(messages,config):
    provider,model,key=config
    if not key:
        raise RuntimeError('模型服务暂未配置')
    received=False;finished=False
    async with httpx.AsyncClient(timeout=httpx.Timeout(120,connect=15)) as client:
        async with client.stream('POST',server.PROVIDERS[provider]['base']+'/chat/completions',json={'model':model,'messages':messages,'stream':True},headers={'Authorization':'Bearer '+key,'Accept':'text/event-stream'}) as r:
            if r.status_code!=200:
                raise RuntimeError('模型接口 HTTP '+str(r.status_code))
            async for line in r.aiter_lines():
                if not line.startswith('data:'):
                    continue
                content=line[5:].strip()
                if content=='[DONE]':
                    finished=True;break
                try:
                    data=json.loads(content)
                except ValueError:
                    continue
                if data.get('error'):
                    raise RuntimeError('模型流式执行失败')
                for choice in data.get('choices',[]):
                    if choice.get('finish_reason'):
                        finished=True
                    text=(choice.get('delta') or {}).get('content')
                    if text:
                        received=True;yield {'type':'delta','text':text}
                if data.get('usage'):
                    yield {'type':'usage','usage':data['usage']}
    if not received or not finished:
        raise RuntimeError('模型连接结束，正文或完成标记不完整')
