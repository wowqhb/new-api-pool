/*
Pool Management — 上游账号 CRUD

设计要点（与 new-api 主体打通）：
  - PoolAccount 表只存元数据 + 脱敏 Key（key_masked）。
  - 真正给 new-api 调用的明文 Key 存在 channels 表里。
  - 新增账号 + 选 Provider + 填 Key + 勾「自动建渠道」 → 后端会同步建一条 new-api Channel，
    并把 channel_id 回写到 pool_accounts.channel_id；这之后号池账号和 new-api 渠道
    是 1:1 强关联，渠道在「渠道管理」可见可选。
  - 编辑账号时填新 Key → 后端会同步更新关联 channel.key（双写一致）。
  - 「查看完整 Key」按钮 → 调 GET /api/pool/accounts/:id/full_key（从关联 channel 读明文）。
*/

import React, { useEffect, useState } from 'react';
import {
  Table,
  Button,
  Space,
  Tag,
  Modal,
  Form,
  Input,
  Select,
  InputNumber,
  Popconfirm,
  Toast,
  DatePicker,
  Banner,
  Typography,
} from '@douyinfe/semi-ui';
import {
  IconPlus,
  IconRefresh,
  IconSearch,
  IconEyeOpened,
  IconCopy,
  IconLink,
} from '@douyinfe/semi-icons';
import { useTranslation } from 'react-i18next';
import { API } from '../../helpers/api';
import { showError, showSuccess, copy } from '../../helpers';
import PoolPageLayout from './Layout';

const STATUS_LABEL = {
  1: { text: '正常', color: 'green' },
  2: { text: '告警', color: 'orange' },
  3: { text: '禁用', color: 'red' },
};

const TYPE_LABEL = {
  official: '官方付费',
  oauth: 'OAuth',
  free: '免费配额',
  third: '第三方代销',
};

// Provider → new-api Channel Type 映射（与 model/channel.go / constant.ChannelType_* 对齐）
const PROVIDER_OPTIONS = [
  { label: 'OpenAI', value: 'openai', channelType: 1 },
  { label: 'Claude / Anthropic', value: 'claude', channelType: 14 },
  { label: 'Gemini / Google', value: 'gemini', channelType: 24 },
  { label: 'DeepSeek', value: 'deepseek', channelType: 36 },
  { label: 'Grok / xAI', value: 'grok', channelType: 1011 },
  { label: 'Mistral', value: 'mistral', channelType: 28 },
  { label: 'Codex', value: 'codex', channelType: 1 },
  { label: 'OpenRouter', value: 'openrouter', channelType: 20 },
  { label: 'Moonshot (Kimi)', value: 'moonshot', channelType: 25 },
  { label: 'Together AI', value: 'together', channelType: 33 },
  { label: 'Cohere', value: 'cohere', channelType: 1003 },
  { label: 'SiliconFlow', value: 'siliconflow', channelType: 45 },
  { label: '智谱 GLM', value: 'zhipu', channelType: 26 },
  { label: '其它', value: 'other', channelType: 8 },
];

const Accounts = () => {
  const { t } = useTranslation();
  const [loading, setLoading] = useState(false);
  const [items, setItems] = useState([]);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(20);
  const [total, setTotal] = useState(0);
  const [keyword, setKeyword] = useState('');
  const [filterProvider, setFilterProvider] = useState('');
  const [filterStatus, setFilterStatus] = useState(0);

  const [modalVisible, setModalVisible] = useState(false);
  const [editing, setEditing] = useState(null);
  const [formApi, setFormApi] = useState(null);

  // 查看完整 Key
  const [fullKeyVisible, setFullKeyVisible] = useState(false);
  const [fullKeyData, setFullKeyData] = useState(null);

  // 一键绑定多候选选择
  const [bindPickerVisible, setBindPickerVisible] = useState(false);
  const [bindPickerData, setBindPickerData] = useState(null); // {account, candidates}
  const [binding, setBinding] = useState({}); // {accountId: true}

  const fetchData = async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams({
        p: String(page),
        page_size: String(pageSize),
      });
      if (keyword) params.set('keyword', keyword);
      if (filterProvider) params.set('provider', filterProvider);
      if (filterStatus) params.set('status', String(filterStatus));
      const res = await API.get(`/api/pool/accounts?${params.toString()}`);
      if (res?.data?.success) {
        const d = res.data.data;
        setItems(d.items || []);
        setTotal(d.total || 0);
      } else {
        showError(res?.data?.message || t('加载账号失败'));
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, pageSize]);

  const openAdd = () => {
    setEditing({
      __new: true,
      account_type: 'official',
      status: 1,
      balance_usd: 0,
      group_name: 'default',
      auto_create_channel: true,
      channel_type: 1,
      channel_base_url: '',
      provider: 'openai',
      name: '',
      key_raw: '',
      notes: '',
    });
    setModalVisible(true);
  };

  const openEdit = (record) => {
    setEditing({
      ...record,
      key_raw: '',
      auto_create_channel: false,
      channel_type:
        record.channel_id > 0
          ? 0
          : PROVIDER_OPTIONS.find((p) => p.value === record.provider)
              ?.channelType || 0,
      channel_base_url: '',
      expire_at_date:
        record.expire_at && record.expire_at > 0
          ? new Date(record.expire_at * 1000)
          : null,
    });
    setModalVisible(true);
  };

  const handleSubmit = async (values) => {
    try {
      const payload = {
        ...values,
        balance_usd: Number(values.balance_usd) || 0,
        expire_at: values.expire_at_date
          ? Math.floor(new Date(values.expire_at_date).getTime() / 1000)
          : 0,
        auto_create_channel: !!values.auto_create_channel,
        channel_type: Number(values.channel_type) || 0,
      };
      delete payload.expire_at_date;
      let res;
      if (editing && !editing.__new) {
        res = await API.put(`/api/pool/accounts/${editing.id}`, payload);
      } else {
        res = await API.post(`/api/pool/accounts`, payload);
      }
      if (res?.data?.success) {
        const d = res.data.data;
        showSuccess(
          editing && !editing.__new
            ? t('更新成功')
            : d?.channel_id
              ? `${t('新增成功')} | ${t('已自动建渠道 #')}${d.channel_id}`
              : t('新增成功'),
        );
        setModalVisible(false);
        fetchData();
      } else {
        showError(res?.data?.message || t('操作失败'));
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  const handleDelete = async (id) => {
    try {
      const res = await API.delete(`/api/pool/accounts/${id}`);
      if (res?.data?.success) {
        showSuccess(t('已删除'));
        fetchData();
      } else {
        showError(res?.data?.message || t('删除失败'));
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  const toggleStatus = async (record, nextStatus) => {
    try {
      const res = await API.put(`/api/pool/accounts/${record.id}`, {
        ...record,
        status: nextStatus,
        key_raw: '',
      });
      if (res?.data?.success) {
        showSuccess(t('状态已更新'));
        fetchData();
      } else {
        showError(res?.data?.message || t('操作失败'));
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  const showFullKey = async (record) => {
    if (!record.channel_id) {
      showError(
        t(
          '该账号未关联渠道，无法查看完整 Key。请编辑账号、勾选「同步建/绑渠道」后重新录入 Key。',
        ),
      );
      return;
    }
    try {
      const res = await API.get(`/api/pool/accounts/${record.id}/full_key`);
      if (res?.data?.success) {
        setFullKeyData({ ...res.data.data, account: record });
        setFullKeyVisible(true);
      } else {
        showError(res?.data?.message || t('获取完整 Key 失败'));
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  const handleBindChannel = async (record, channelId = 0) => {
    setBinding((s) => ({ ...s, [record.id]: true }));
    try {
      const res = await API.post(`/api/pool/accounts/${record.id}/bind`, {
        channel_id: channelId || 0,
      });
      if (res?.data?.success) {
        const d = res.data.data;
        if (d.bound) {
          showSuccess(
            `${t('已绑定到渠道')} #${d.channel_id} (${d.channel_name})`,
          );
          setBindPickerVisible(false);
          fetchData();
        } else if (d.candidates?.length > 1) {
          // 多个候选 → 弹出选择 Modal
          setBindPickerData({ account: record, candidates: d.candidates });
          setBindPickerVisible(true);
        } else {
          showError(d.hint || t('未能自动绑定'));
        }
      } else {
        showError(res?.data?.message || t('一键绑定失败'));
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    } finally {
      setBinding((s) => ({ ...s, [record.id]: false }));
    }
  };

  const copyFullKey = async (record) => {
    if (!record.channel_id) {
      showError(t('该账号未关联渠道，无法复制（请先把 Key 同步到渠道）'));
      return;
    }
    try {
      const res = await API.get(`/api/pool/accounts/${record.id}/full_key`);
      if (res?.data?.success) {
        const k = res.data.data?.key || '';
        if (!k) {
          showError(t('关联渠道无 Key'));
          return;
        }
        await copy(k);
        Toast.success(t('已复制完整 Key'));
      } else {
        showError(res?.data?.message || t('获取完整 Key 失败'));
      }
    } catch (e) {
      showError(e?.message || t('网络异常'));
    }
  };

  const columns = [
    { title: 'ID', dataIndex: 'id', width: 60 },
    { title: t('名称'), dataIndex: 'name' },
    {
      title: t('Provider'),
      dataIndex: 'provider',
      render: (v) => <Tag>{v}</Tag>,
    },
    {
      title: t('类型'),
      dataIndex: 'account_type',
      render: (v) => TYPE_LABEL[v] || v,
    },
    {
      title: t('Key'),
      dataIndex: 'key_masked',
      width: 220,
      render: (v, r) => (
        <Space>
          <span className='font-mono text-xs'>{v || '-'}</span>
          <Button
            size='small'
            theme='borderless'
            icon={<IconCopy />}
            disabled={!r.channel_id}
            onClick={() => copyFullKey(r)}
            title={t('复制完整 Key（从关联渠道读取）')}
          />
          <Button
            size='small'
            theme='borderless'
            icon={<IconEyeOpened />}
            disabled={!r.channel_id}
            onClick={() => showFullKey(r)}
            title={t('查看完整 Key')}
          />
        </Space>
      ),
    },
    {
      title: t('渠道'),
      dataIndex: 'channel_id',
      width: 150,
      render: (v, r) =>
        v && v > 0 ? (
          <a
            href={`/console/channel?keyword=${v}`}
            target='_blank'
            rel='noreferrer'
            title={t('在「渠道管理」打开')}
          >
            <Tag color='green'>
              <IconLink size='small' /> {t('已绑定')} #{v}
            </Tag>
          </a>
        ) : (
          <Button
            size='small'
            type='primary'
            theme='light'
            loading={!!binding[r.id]}
            onClick={() => handleBindChannel(r)}
          >
            {t('一键绑定')}
          </Button>
        ),
    },
    {
      title: t('余额 ($)'),
      dataIndex: 'balance_usd',
      render: (v) => (Number(v) || 0).toFixed(2),
    },
    { title: t('分组'), dataIndex: 'group_name' },
    {
      title: t('到期时间'),
      dataIndex: 'expire_at',
      render: (v) =>
        v && v > 0 ? new Date(v * 1000).toLocaleDateString() : t('永久'),
    },
    {
      title: t('状态'),
      dataIndex: 'status',
      render: (v) => {
        const s = STATUS_LABEL[v] || { text: '?', color: 'grey' };
        return <Tag color={s.color}>{s.text}</Tag>;
      },
    },
    {
      title: t('操作'),
      width: 240,
      render: (_, record) => (
        <Space>
          <Button size='small' onClick={() => openEdit(record)}>
            {t('编辑')}
          </Button>
          {record.status === 1 ? (
            <Button size='small' onClick={() => toggleStatus(record, 3)}>
              {t('禁用')}
            </Button>
          ) : (
            <Button size='small' onClick={() => toggleStatus(record, 1)}>
              {t('启用')}
            </Button>
          )}
          <Popconfirm
            title={t('确认删除？')}
            content={t('删除后不可恢复，关联渠道仍保留')}
            onConfirm={() => handleDelete(record.id)}
          >
            <Button size='small' type='danger'>
              {t('删除')}
            </Button>
          </Popconfirm>
        </Space>
      ),
    },
  ];

  return (
    <PoolPageLayout
      title={t('上游账号')}
      subtitle={t(
        '号池账号 = new-api 渠道的 1:1 镜像，记录付费/免费 Key、OAuth、第三方代销账号；新增/改 Key 时自动同步到「渠道管理」。',
      )}
      extra={
        <Space>
          <Button icon={<IconRefresh />} size='small' onClick={fetchData}>
            {t('刷新')}
          </Button>
          <Button
            icon={<IconPlus />}
            type='primary'
            theme='solid'
            size='small'
            onClick={openAdd}
          >
            {t('新增账号')}
          </Button>
        </Space>
      }
    >
      <Banner
        type='info'
        description={t(
          '本表只存元数据 + 脱敏 Key；明文 Key 与 new-api 渠道 1:1 同步存储于 channels 表，可在「渠道管理」直接调用。点 Key 列右侧「眼睛/复制」可读出完整明文。',
        )}
        closeIcon={null}
        className='mb-3'
      />

      <Space className='mb-3' wrap>
        <Input
          prefix={<IconSearch />}
          placeholder={t('搜索名称 / 备注')}
          value={keyword}
          onChange={(v) => setKeyword(v)}
          style={{ width: 220 }}
          onEnterPress={() => {
            setPage(1);
            fetchData();
          }}
        />
        <Select
          placeholder={t('Provider')}
          value={filterProvider}
          onChange={(v) => setFilterProvider(v || '')}
          optionList={[{ label: t('全部'), value: '' }, ...PROVIDER_OPTIONS]}
          style={{ width: 160 }}
        />
        <Select
          placeholder={t('状态')}
          value={filterStatus}
          onChange={(v) => setFilterStatus(v || 0)}
          optionList={[
            { label: t('全部'), value: 0 },
            { label: t('正常'), value: 1 },
            { label: t('告警'), value: 2 },
            { label: t('禁用'), value: 3 },
          ]}
          style={{ width: 120 }}
        />
        <Button
          onClick={() => {
            setPage(1);
            fetchData();
          }}
        >
          {t('应用过滤')}
        </Button>
      </Space>

      <Table
        loading={loading}
        columns={columns}
        dataSource={items}
        rowKey='id'
        pagination={{
          currentPage: page,
          pageSize,
          total,
          onPageChange: setPage,
          onPageSizeChange: setPageSize,
          showSizeChanger: true,
        }}
      />

      <Modal
        title={
          editing && !editing.__new ? t('编辑上游账号') : t('新增上游账号')
        }
        visible={modalVisible}
        onCancel={() => setModalVisible(false)}
        footer={null}
        width={680}
        destroyOnClose
      >
        <Form
          key={editing?.id || 'new'}
          getFormApi={setFormApi}
          onSubmit={handleSubmit}
          initValues={editing || {}}
          labelPosition='left'
          labelWidth={120}
          onValueChange={(vals, changed) => {
            // 选了 Provider 自动联动 channel_type
            if (changed.provider) {
              const p = PROVIDER_OPTIONS.find((x) => x.value === vals.provider);
              if (p && (!vals.channel_type || vals.channel_type <= 0)) {
                formApi?.setValue('channel_type', p.channelType);
              }
            }
          }}
        >
          <Form.Input
            field='name'
            label={t('名称')}
            rules={[{ required: true, message: t('必填') }]}
          />
          <Form.Select
            field='provider'
            label={t('Provider')}
            optionList={PROVIDER_OPTIONS.map((p) => ({
              label: `${p.label} (channel_type=${p.channelType})`,
              value: p.value,
            }))}
            rules={[{ required: true, message: t('必填') }]}
            extraText={t('选定后会自动给「渠道类型」填默认值')}
          />
          <Form.Select
            field='account_type'
            label={t('类型')}
            optionList={[
              { label: TYPE_LABEL.official, value: 'official' },
              { label: TYPE_LABEL.oauth, value: 'oauth' },
              { label: TYPE_LABEL.free, value: 'free' },
              { label: TYPE_LABEL.third, value: 'third' },
            ]}
          />
          <Form.Input
            field='key_raw'
            label={t('Key (原始)')}
            placeholder={
              editing && !editing.__new
                ? t('留空表示不修改；填写则同步更新关联渠道')
                : t('录入后系统会同步写入对应 new-api 渠道')
            }
            extraText={t(
              '本表只存脱敏掩码；完整明文存在关联渠道里，可点列表 Key 列「眼睛」查看。',
            )}
          />
          <Form.Switch
            field='auto_create_channel'
            label={t('同步建/绑渠道')}
            extraText={t(
              '勾选 = 提交时若 channel_id 为 0 且填了 Key，会按下方「渠道类型」自动建一条 new-api Channel 并写入 Key',
            )}
          />
          <Form.InputNumber
            field='channel_type'
            label={t('渠道类型 ID')}
            min={0}
            extraText={t(
              '与 new-api Channel.Type 对应；常见：1=OpenAI、14=Anthropic、20=OpenRouter、24=Gemini、25=Moonshot、28=Mistral、36=DeepSeek',
            )}
          />
          <Form.Input
            field='channel_base_url'
            label={t('渠道 BaseURL')}
            placeholder={t('留空表示用该 channel_type 的默认地址')}
          />
          <Form.InputNumber
            field='balance_usd'
            label={t('余额 ($)')}
            min={0}
          />
          <Form.Input
            field='group_name'
            label={t('分组')}
            extraText={t(
              '与 new-api 渠道 group 字段一致：提交时同步写到 channel.group',
            )}
          />
          <Form.InputNumber
            field='channel_id'
            label={t('已绑渠道 ID')}
            min={0}
            placeholder='0 = 未绑定（建议勾选「同步建/绑渠道」自动生成）'
          />
          <Form.DatePicker
            field='expire_at_date'
            label={t('到期时间')}
            type='date'
          />
          <Form.Select
            field='status'
            label={t('状态')}
            optionList={[
              { label: t('正常'), value: 1 },
              { label: t('告警'), value: 2 },
              { label: t('禁用'), value: 3 },
            ]}
          />
          <Form.TextArea field='notes' label={t('备注')} rows={2} />
          <div className='mt-2 text-right'>
            <Space>
              <Button onClick={() => setModalVisible(false)}>
                {t('取消')}
              </Button>
              <Button type='primary' theme='solid' htmlType='submit'>
                {t('保存')}
              </Button>
            </Space>
          </div>
        </Form>
      </Modal>

      <Modal
        title={t('完整 Key（来自关联渠道）')}
        visible={fullKeyVisible}
        onCancel={() => setFullKeyVisible(false)}
        footer={
          <Space>
            <Button
              type='primary'
              theme='solid'
              icon={<IconCopy />}
              onClick={async () => {
                if (fullKeyData?.key) {
                  await copy(fullKeyData.key);
                  Toast.success(t('已复制'));
                }
              }}
            >
              {t('复制')}
            </Button>
            <Button onClick={() => setFullKeyVisible(false)}>
              {t('关闭')}
            </Button>
          </Space>
        }
        width={620}
      >
        {fullKeyData && (
          <div>
            <div className='mb-2 text-sm text-gray-600'>
              {t('账号')}：{fullKeyData.account?.name} (
              {fullKeyData.account?.provider})
            </div>
            <div className='mb-2 text-sm text-gray-600'>
              {t('关联渠道')}：#{fullKeyData.channel_id}{' '}
              {fullKeyData.channel_name} ({t('类型')}={fullKeyData.channel_type}
              )
            </div>
            <Typography.Paragraph
              copyable
              code
              style={{ wordBreak: 'break-all' }}
            >
              {fullKeyData.key || '(empty)'}
            </Typography.Paragraph>
            <div className='text-xs text-gray-400 mt-2'>
              {t(
                '提示：在 new-api「渠道管理」编辑此渠道也能改 Key，两边任改一边都会同步。',
              )}
            </div>
          </div>
        )}
      </Modal>

      <Modal
        title={t('选择要绑定的渠道')}
        visible={bindPickerVisible}
        onCancel={() => setBindPickerVisible(false)}
        footer={
          <Button onClick={() => setBindPickerVisible(false)}>
            {t('取消')}
          </Button>
        }
        width={520}
      >
        {bindPickerData && (
          <div>
            <div className='mb-2 text-sm text-gray-600'>
              {t('账号')}：<b>{bindPickerData.account?.name}</b> (
              {bindPickerData.account?.provider})
            </div>
            <div className='mb-2 text-sm text-gray-500'>
              {t('命中多个候选渠道，请选择一个绑定：')}
            </div>
            <div style={{ maxHeight: 360, overflow: 'auto' }}>
              {bindPickerData.candidates.map((c) => (
                <div
                  key={c.id}
                  className='flex items-center justify-between border-b py-2'
                >
                  <span>
                    <Tag>#{c.id}</Tag>
                    <span className='ml-2'>{c.name}</span>
                    <span className='ml-2 text-xs text-gray-400'>
                      type={c.type}
                    </span>
                  </span>
                  <Button
                    size='small'
                    type='primary'
                    onClick={() =>
                      handleBindChannel(bindPickerData.account, c.id)
                    }
                  >
                    {t('绑定')}
                  </Button>
                </div>
              ))}
            </div>
          </div>
        )}
      </Modal>
    </PoolPageLayout>
  );
};

export default Accounts;
